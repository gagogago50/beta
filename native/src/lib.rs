mod api;

use crossbeam::atomic::AtomicCell;
use crossbeam::queue::SegQueue;
use dashmap::DashMap;
use once_cell::sync::Lazy;
use parking_lot::Mutex;
use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicPtr, AtomicU32, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::runtime::Runtime;

pub static RUNTIME: Lazy<Runtime> =
    Lazy::new(|| Runtime::new().expect("Failed to create tokio runtime"));

// ─── Session identity ───────────────────────────────────────────────

/// Stable handle of one connection to one virtual server.
///
/// `0` is reserved: it means "no session" and is used for engine-wide
/// diagnostics (panic logs), never for a real connection.
pub type ConnectionId = u64;

/// Monotonic source of connection ids. Persistent for the process lifetime,
/// never reused, so a late event from an aborted or old session can never be
/// misattributed to a brand-new one.
pub static NEXT_CONNECTION_ID: Lazy<AtomicU64> = Lazy::new(|| AtomicU64::new(1));

pub fn next_connection_id() -> ConnectionId {
    NEXT_CONNECTION_ID.fetch_add(1, Ordering::Relaxed)
}

// ─── Command queue ───────────────────────────────────────────────────

#[derive(Debug)]
pub enum Command {
    SendMessage {
        target_mode: u8,
        target_cid: u64,
        message: String,
    },
    MoveChannel {
        client_id: u16,
        channel_id: u64,
        channel_password: Option<String>,
    },
    SetMuted {
        input: bool,
        output: bool,
    },
    /// Away/AFK flag with an optional message shown to other clients.
    SetAway {
        away: bool,
        message: Option<String>,
    },
    /// In-session nickname change.
    SetNickname {
        name: String,
    },
    /// Kick a client from its channel or from the server, with a reason.
    KickClient {
        client_id: u16,
        from_server: bool,
        reason: Option<String>,
    },
    /// Ban a client for `seconds` (0 = permanent), with a reason.
    BanClient {
        client_id: u16,
        seconds: u64,
        reason: Option<String>,
    },
    /// Starts a file download (`ftinitdownload`). The engine answers with a
    /// `file_transfer` event once the TCP transfer finished or failed.
    DownloadFile {
        transfer_id: u16,
        channel_id: u64,
        channel_password: String,
        remote_path: String,
    },
    /// Starts a file upload (`ftinitupload`). The engine streams [source_path]
    /// to the server and answers with `file_transfer_progress` (periodically)
    /// then a final `file_transfer` event.
    UploadFile {
        transfer_id: u16,
        channel_id: u64,
        channel_password: String,
        remote_path: String,
        source_path: String,
        size: u64,
        overwrite: bool,
    },
    /// Lists the files of a channel directory (`ftgetfilelist`). The engine
    /// answers with a `ServerFileList` event once the server finishes.
    RequestFileList {
        request_id: u32,
        channel_id: u64,
        channel_password: String,
        path: String,
    },
    /// Deletes a file from a channel directory (`ftdeletefile`).
    DeleteFile {
        channel_id: u64,
        channel_password: String,
        path: String,
    },
    /// Creates a channel directory (`ftcreatedir`).
    CreateDirectory {
        channel_id: u64,
        channel_password: String,
        path: String,
    },
    /// Creates a channel in [parent_id] (0 = the root). The server enforces
    /// the `b_channel_create_*` permission.
    CreateChannel {
        parent_id: u64,
        name: String,
        topic: Option<String>,
        description: Option<String>,
        password: Option<String>,
        max_clients: Option<i32>,
        permanent: bool,
        semi_permanent: bool,
    },
    /// Edits an existing channel. Only the provided fields are changed.
    EditChannel {
        channel_id: u64,
        name: Option<String>,
        topic: Option<String>,
        description: Option<String>,
        password: Option<String>,
        has_password: Option<bool>,
        max_clients: Option<i32>,
        permanent: Option<bool>,
        semi_permanent: Option<bool>,
    },
    /// Deletes a channel. When [force] is true the tree is deleted even if it
    /// still has sub-channels.
    DeleteChannel {
        channel_id: u64,
        force: bool,
    },
    /// Moves (re-orders / re-parents) a channel in the tree.
    MoveChannelTree {
        channel_id: u64,
        parent_id: u64,
        order: Option<u64>,
    },
    /// Poke: a message that pops up on the target's screen.
    PokeClient {
        client_id: u16,
        message: String,
    },
    /// Channel commander flag (voice is heard in every subscribed channel of
    /// the server group's scope). Requires a permission the server enforces.
    SetChannelCommander {
        enabled: bool,
    },
    Disconnect,
    SendAudio {
        data: Vec<f32>,
    },
}

impl Command {
    /// Flood cost of a control command, in tokens.
    ///
    /// TeamSpeak servers count "flood points" per client and kick or ban past
    /// a threshold; a text message is the most expensive thing a normal client
    /// sends, a mute update the cheapest. Audio and Disconnect are not control
    /// commands and never go through the budget.
    pub fn flood_cost(&self) -> f32 {
        match self {
            Command::SendMessage { .. } => 2.0,
            Command::MoveChannel { .. } => 1.5,
            Command::SetMuted { .. } => 0.5,
            Command::SetAway { .. } => 0.5,
            Command::SetChannelCommander { .. } => 0.5,
            // A rename is broadcast to every client on the server, so servers
            // weigh it heavily; keep it the most expensive state update.
            Command::SetNickname { .. } => 2.0,
            // Moderation commands are rare but heavily audited server-side;
            // price them like a text message so a stuck UI cannot spam them.
            Command::KickClient { .. } | Command::BanClient { .. } => 2.0,
            Command::PokeClient { .. } => 2.0,
            // Cheap on the command channel: the payload travels on a separate
            // TCP connection, only the handshake is a command.
            Command::DownloadFile { .. } | Command::UploadFile { .. } => 1.0,
            // File management (list / delete / mkdir) is a normal control
            // command; price it like a file-handshake so a stuck file browser
            // cannot flood the server.
            Command::RequestFileList { .. }
            | Command::DeleteFile { .. }
            | Command::CreateDirectory { .. } => 1.0,
            // Channel administration is audited and permission-gated; price it
            // like a text message so a stuck UI cannot create a flood of
            // channels.
            Command::CreateChannel { .. }
            | Command::EditChannel { .. }
            | Command::DeleteChannel { .. }
            | Command::MoveChannelTree { .. } => 2.0,
            Command::SendAudio { .. } | Command::Disconnect => 0.0,
        }
    }

    /// Whether the budget may drop an older queued command in favour of this
    /// one. Only true for commands that carry a *state* the server should end
    /// up in: sending "move to channel 5" twice is pointless, but dropping a
    /// text message would lose user content.
    fn supersedes(&self, other: &Command) -> bool {
        matches!(
            (self, other),
            (Command::MoveChannel { .. }, Command::MoveChannel { .. })
                | (Command::SetMuted { .. }, Command::SetMuted { .. })
                | (Command::SetAway { .. }, Command::SetAway { .. })
                | (Command::SetNickname { .. }, Command::SetNickname { .. })
                | (
                    Command::RequestFileList { .. },
                    Command::RequestFileList { .. }
                )
                | (
                    Command::SetChannelCommander { .. },
                    Command::SetChannelCommander { .. }
                )
        )
    }
}

/// Token bucket + pending queue protecting the connection from flood kicks.
///
/// The UI can legitimately produce bursts (a user tapping through channels);
/// the server cannot. Commands are therefore queued and released at a
/// sustainable rate instead of being dropped, so the user's last intention
/// always reaches the server — just slightly later.
pub struct CommandBudget {
    tokens: f32,
    capacity: f32,
    refill_per_sec: f32,
    last_refill: Instant,
    /// While set, the budget runs in degraded mode after the server complained
    /// about flooding.
    degraded_until: Option<Instant>,
    queue: VecDeque<Command>,
    /// Commands dropped because the queue was full — surfaced for diagnostics.
    pub dropped: u64,
}

impl CommandBudget {
    /// Burst size and sustained rate. Deliberately below what a default
    /// TeamSpeak server tolerates: being throttled by ourselves is invisible,
    /// being banned is not.
    pub const CAPACITY: f32 = 8.0;
    pub const REFILL_PER_SEC: f32 = 3.0;
    /// Degraded settings applied after a flood error from the server.
    pub const DEGRADED_CAPACITY: f32 = 2.0;
    pub const DEGRADED_REFILL_PER_SEC: f32 = 0.5;
    pub const DEGRADED_DURATION: Duration = Duration::from_secs(30);
    /// Bounded queue: past this many pending commands the oldest is dropped,
    /// because a backlog that large is a UI bug, not a user intention.
    pub const MAX_QUEUE: usize = 32;

    pub fn new(now: Instant) -> Self {
        Self {
            tokens: Self::CAPACITY,
            capacity: Self::CAPACITY,
            refill_per_sec: Self::REFILL_PER_SEC,
            last_refill: now,
            degraded_until: None,
            queue: VecDeque::new(),
            dropped: 0,
        }
    }

    pub fn pending(&self) -> usize {
        self.queue.len()
    }

    pub fn is_degraded(&self) -> bool {
        self.degraded_until.is_some()
    }

    /// Halves the throughput for [`Self::DEGRADED_DURATION`] after the server
    /// reported flooding, and drops the current token balance so the next
    /// command waits.
    pub fn enter_degraded(&mut self, now: Instant) {
        self.degraded_until = Some(now + Self::DEGRADED_DURATION);
        self.capacity = Self::DEGRADED_CAPACITY;
        self.refill_per_sec = Self::DEGRADED_REFILL_PER_SEC;
        self.tokens = 0.0;
    }

    fn refill(&mut self, now: Instant) {
        if let Some(until) = self.degraded_until {
            if now >= until {
                self.degraded_until = None;
                self.capacity = Self::CAPACITY;
                self.refill_per_sec = Self::REFILL_PER_SEC;
            }
        }
        let elapsed = now.saturating_duration_since(self.last_refill);
        if elapsed.is_zero() {
            return;
        }
        self.last_refill = now;
        self.tokens =
            (self.tokens + elapsed.as_secs_f32() * self.refill_per_sec).min(self.capacity);
    }

    /// Queues a command, replacing a superseded one when possible.
    pub fn enqueue(&mut self, command: Command) {
        if let Some(slot) = self
            .queue
            .iter_mut()
            .find(|queued| command.supersedes(queued))
        {
            *slot = command;
            return;
        }
        if self.queue.len() >= Self::MAX_QUEUE {
            self.queue.pop_front();
            self.dropped += 1;
        }
        self.queue.push_back(command);
    }

    /// Returns the next command the budget can afford, consuming its cost.
    /// Returns `None` when the queue is empty or no token is available yet.
    pub fn take_ready(&mut self, now: Instant) -> Option<Command> {
        self.refill(now);
        let cost = self.queue.front()?.flood_cost();
        if self.tokens < cost {
            return None;
        }
        self.tokens -= cost;
        self.queue.pop_front()
    }
}

/// A download waiting for the server's `notifystartdownload` answer.
#[derive(Debug, Clone)]
pub struct PendingTransfer {
    /// Where the payload is written once received.
    pub target_path: String,
    /// Hard cap; the server-announced size is refused above it.
    pub max_bytes: u64,
    /// Logical name, echoed back to Dart so the UI can match the result.
    pub remote_path: String,
}

/// An in-flight upload, kept until the server answers with the transfer stream
/// so the event loop can match the tsclientlib handle to the requested file.
#[derive(Debug, Clone)]
pub struct UploadJob {
    /// Our transfer id (the one returned to Dart).
    pub transfer_id: u16,
    /// Local file to stream to the server.
    pub source_path: String,
    /// Logical name, echoed back for the UI.
    pub remote_path: String,
}

// ─── Per-session bookkeeping ────────────────────────────────────────

/// Everything that belongs to one connection to one virtual server.
///
/// The connection state lives behind an `Arc<Mutex<..>>` so the connection
/// event loop (owned by a long-lived tokio task) and the synchronous FFI
/// entry points can lock the *same* state without holding a `DashMap` guard
/// across an `await`. Each `connection_id` is unique for the process lifetime,
/// so a session is never confused with another one.
pub struct Session {
    pub state: Arc<Mutex<TsConnection>>,
    pub command_tx: Mutex<Option<tokio::sync::mpsc::UnboundedSender<Command>>>,
    pub command_budget: Mutex<CommandBudget>,
    pub pending_transfers: Mutex<HashMap<u16, PendingTransfer>>,
    /// In-flight uploads keyed by the tsclientlib transfer handle (the
    /// `client_filetransfer_id` chosen by the engine). Removed once the stream
    /// is handed over to the upload task.
    pub upload_jobs: Mutex<HashMap<u16, UploadJob>>,
    /// In-flight `ftgetfilelist` requests, keyed by `(channel_id, path)` so the
    /// engine can correlate the multi-part `FileList`/`FileListFinished` answer
    /// back to the `request_id` handed to Dart.
    pub pending_file_requests: Mutex<HashMap<(u64, String), u32>>,
    pub next_transfer_id: AtomicU32,
    /// Monotonic source of file-list request ids.
    pub next_request_id: AtomicU32,
    /// Host part of the address the user connected to. Used as the fallback
    /// target for file transfers when the server does not pin an IP.
    pub server_host: Mutex<String>,
    /// Monotonic generation of this session, used only for diagnostics.
    pub generation: u64,
    /// Set by the connection event loop, so a dead loop can be detected
    /// without waiting on a mutex.
    pub event_loop_alive: AtomicBool,
    /// Handle of the in-flight connection attempt, so `ts_cancel_connect` can
    /// abort it instead of leaving a task running behind a dismissed UI.
    pub connect_task: Mutex<Option<tokio::task::JoinHandle<()>>>,
    /// Stash of the live `Connection`, used only when the event loop is dead
    /// (app swiped away) to perform a synchronous disconnect.
    pub connection: Mutex<Option<tsclientlib::Connection>>,
}

impl Session {
    pub fn new(id: ConnectionId, state: TsConnection) -> Self {
        Self {
            state: Arc::new(Mutex::new(state)),
            command_tx: Mutex::new(None),
            command_budget: Mutex::new(CommandBudget::new(Instant::now())),
            pending_transfers: Mutex::new(HashMap::new()),
            upload_jobs: Mutex::new(HashMap::new()),
            pending_file_requests: Mutex::new(HashMap::new()),
            next_transfer_id: AtomicU32::new(1),
            next_request_id: AtomicU32::new(1),
            server_host: Mutex::new(String::new()),
            generation: id,
            event_loop_alive: AtomicBool::new(false),
            connect_task: Mutex::new(None),
            connection: Mutex::new(None),
        }
    }
}

/// All live sessions, keyed by their unique `connection_id`.
pub static SESSIONS: Lazy<DashMap<ConnectionId, Session>> = Lazy::new(DashMap::new);

/// The TeamSpeak identity is engine-wide: one identity is used by every
/// connected server, since TS3 client identities are derived from a single
/// keypair that is the same on every virtual server.
pub static IDENTITY_STASH: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));

/// Set when the cpal output stream should be rebuilt (device route change,
/// stream error, or explicit restart request from the Android side). The
/// maintenance task performs the rebuild on its 500ms tick.
pub static OUTPUT_RESTART_REQUESTED: Lazy<AtomicBool> = Lazy::new(|| AtomicBool::new(false));

/// Per-client volume in decibels, keyed by the client's *user UID*.
///
/// Same-store-same-sound on every server: a TS3 user UID is derived from the
/// client's identity and is identical across all servers, so a per-user volume
/// is naturally global rather than per-session. This is why it lives here and
/// not in [`Session`].
pub static CLIENT_VOLUMES: Lazy<Mutex<HashMap<String, f32>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

#[inline]
pub fn session(id: ConnectionId) -> Option<Arc<Mutex<TsConnection>>> {
    SESSIONS.get(&id).map(|s| s.state.clone())
}

/// Returns `true` when at least one session is currently connected, which lets
/// the single output stream stay alive across reconnects while tearing it
/// down once the last server is gone.
pub fn any_session_listening() -> bool {
    SESSIONS.iter().any(|s| s.state.lock().connected)
}

// ─── Event delivery ─────────────────────────────────────────────────

/// Global, cross-session event queue, drained by a single `ts_poll_events`.
///
/// A single queue — rather than one per session — means Dart needs one poll
/// timer and one FFI call for every server; events are attributed to their
/// session by the `connection_id` wrapper.
pub static EVENT_QUEUE: Lazy<Mutex<VecDeque<EnvelopedEvent>>> =
    Lazy::new(|| Mutex::new(VecDeque::new()));

/// An engine event tagged with the session it belongs to. `connection_id == 0`
/// marks an engine-wide diagnostic.
#[derive(Debug, Clone, serde::Serialize)]
pub struct EnvelopedEvent {
    pub connection_id: ConnectionId,
    #[serde(flatten)]
    pub event: TsEvent,
}

/// Dart NativeCallable listener used only as an edge-triggered wake-up signal.
/// Events themselves remain owned by Rust and are drained through ts_poll_events.
pub static EVENT_NOTIFIER: AtomicPtr<()> = AtomicPtr::new(std::ptr::null_mut());

pub fn notify_event_listener() {
    let pointer = EVENT_NOTIFIER.load(std::sync::atomic::Ordering::Acquire);
    if pointer.is_null() {
        return;
    }
    // The pointer is registered by Dart as a NativeCallable.listener and may be
    // invoked from Rust worker threads. It stays valid for the process lifetime.
    let callback: extern "C" fn() = unsafe { std::mem::transmute(pointer) };
    callback();
}

pub fn push_event(connection_id: ConnectionId, event: TsEvent) {
    EVENT_QUEUE.lock().push_back(EnvelopedEvent {
        connection_id,
        event,
    });
    notify_event_listener();
}

/// Engine-wide diagnostic (panic logs, spurious warnings) not tied to a
/// particular server.
pub fn push_global_event(event: TsEvent) {
    push_event(0, event);
}

// ─── Types for Dart ─────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Serialize)]
#[serde(tag = "type")]
pub enum TsEvent {
    #[serde(rename = "connected")]
    Connected {
        server_name: String,
        client_id: u32,
        voice_encryption_mode: String,
        /// Stable identity of the virtual server (base64 of the public key
        /// hash). Used to scope caches — a server name can change, this
        /// cannot.
        server_uid: String,
        /// `virtualserver_welcomemessage`: shown to every new client on connect.
        welcome_message: String,
        /// `virtualserver_hostmessage`: a server-operator notice.
        host_message: String,
        /// `virtualserver_hostmessage_mode`: 0 = none, 1 = modal, 2 = chat,
        /// 3 = disconnect.
        host_message_mode: u8,
        /// `virtualserver_maxclients`: capacity of the virtual server.
        max_clients: u32,
        /// `virtualserver_needed_identity_security_level`: the identity level
        /// this server requires; a lower level is refused.
        needed_identity_security_level: u32,
    },
    #[serde(rename = "disconnected")]
    Disconnected {
        reason: String,
        /// True when the local user asked for it (button, notification,
        /// swipe-away). False means the link dropped on its own, which is the
        /// only case where an automatic reconnect is legitimate.
        expected: bool,
    },
    #[serde(rename = "text_message")]
    TextMessage {
        from_client: String,
        from_client_id: u32,
        target_mode: u8,
        message: String,
    },
    #[serde(rename = "client_joined")]
    ClientJoined {
        client_id: u32,
        nickname: String,
        channel_id: u32,
    },
    #[serde(rename = "client_left")]
    ClientLeft { client_id: u32, nickname: String },
    #[serde(rename = "channels_updated")]
    ChannelsUpdated {},
    #[serde(rename = "diag")]
    Diag { msg: String },
    #[serde(rename = "error")]
    Error { message: String },
    #[serde(rename = "command_error")]
    CommandError {
        code: String,
        message: String,
        missing_permission: Option<String>,
    },
    #[serde(rename = "network_stats")]
    NetworkStats {
        rtt_ms: u64,
        rtt_deviation_ms: u64,
        /// Inter-arrival jitter computed by the engine from consecutive RTT
        /// samples (the mean absolute difference between successive RTTs).
        jitter_ms: u64,
        packet_loss_percent: f32,
    },
    /// Explicit connection phase transition. Mirrors the state machine the
    /// desktop client shows in its status bar: resolving → connecting →
    /// authenticating → connected.
    #[serde(rename = "connection_phase")]
    ConnectionPhase { phase: String },
    /// Result of a file transfer started with `ts_download_file` or
    /// `ts_upload_file`.
    #[serde(rename = "file_transfer")]
    FileTransfer {
        transfer_id: u32,
        remote_path: String,
        /// Local path on success, empty on failure.
        local_path: String,
        bytes: u64,
        ok: bool,
        /// Machine-readable failure cause: `too_large`, `network`, `io`,
        /// `refused`, `cancelled`.
        error: Option<String>,
    },
    /// Periodic progress of an in-flight upload, so the UI can show a bar
    /// instead of an indeterminate spinner.
    #[serde(rename = "file_transfer_progress")]
    FileTransferProgress {
        transfer_id: u32,
        remote_path: String,
        bytes: u64,
        total_bytes: u64,
    },
    /// Result of a `ftgetfilelist` request for one channel directory. Emitted
    /// when the server sends the terminating `FileListFinished` part. `ok` is
    /// false when the request was dropped locally or matched no pending reply.
    #[serde(rename = "file_list")]
    ServerFileList {
        request_id: u32,
        channel_id: u32,
        path: String,
        /// `true` = the server answered with a full listing; `false` = error.
        ok: bool,
        error: Option<String>,
        files: Vec<TsServerFile>,
    },
    /// Outgoing commands are being paced to stay under the server's flood
    /// threshold. `pending` is the current backlog.
    #[serde(rename = "command_throttled")]
    CommandThrottled { pending: u32, degraded: bool },
    /// Structured connection failure. `kind` is derived from the tsclientlib
    /// error variant — never from message text — so the UI and the reconnect
    /// policy can branch on it reliably.
    #[serde(rename = "connect_failed")]
    ConnectFailed {
        kind: String,
        phase: String,
        message: String,
        /// False for failures a retry cannot fix (bad password, ban,
        /// insufficient identity level, user cancellation).
        retryable: bool,
    },
}

/// Phase of the connection state machine, as reported to Dart.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectPhase {
    Resolving,
    Connecting,
    Authenticating,
    Connected,
}

impl ConnectPhase {
    pub fn as_str(self) -> &'static str {
        match self {
            ConnectPhase::Resolving => "resolving",
            ConnectPhase::Connecting => "connecting",
            ConnectPhase::Authenticating => "authenticating",
            ConnectPhase::Connected => "connected",
        }
    }
}

/// A connection attempt failure with everything the UI and the reconnect
/// policy need, without parsing any human-readable text.
#[derive(Debug, Clone)]
pub struct ConnectFailure {
    pub kind: &'static str,
    pub phase: ConnectPhase,
    pub message: String,
    pub retryable: bool,
}

impl ConnectFailure {
    pub fn new(kind: &'static str, phase: ConnectPhase, message: String, retryable: bool) -> Self {
        Self {
            kind,
            phase,
            message,
            retryable,
        }
    }

    pub fn into_event(self) -> TsEvent {
        TsEvent::ConnectFailed {
            kind: self.kind.to_string(),
            phase: self.phase.as_str().to_string(),
            message: self.message,
            retryable: self.retryable,
        }
    }
}

/// One entry of a server channel's file listing (`ftgetfilelist`).
#[derive(Debug, Clone, serde::Serialize)]
pub struct TsServerFile {
    pub name: String,
    pub size: u64,
    /// Seconds-since-epoch of the last modification, 0 when unknown.
    pub modified: u64,
    /// `true` for a directory, `false` for a regular file.
    pub is_directory: bool,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct TsChannel {
    pub id: u32,
    pub name: String,
    pub parent_id: u32,
    pub topic: String,
    pub has_password: bool,
    pub client_count: u32,
    pub order: u32,
    /// Talk power required to speak in this channel (`channel_needed_talk_power`).
    pub needed_talk_power: i32,
    /// Maximum number of clients: `-1` = unlimited, `-2` = inherited, else the cap.
    pub max_clients: i32,
    /// TeamSpeak codec id: 0=Speex NB, 1=Speex WB, 2=Speex UWB, 3=Celt mono,
    /// 4=Opus voice, 5=Opus music.
    pub codec: u8,
    /// Codec quality 0..10, when the server reports it.
    pub codec_quality: u8,
    /// 0 = temporary (deleted when empty), 1 = permanent (survives restart),
    /// 2 = semi-permanent (deleted on server restart).
    pub channel_type: u8,
    /// Whether this is the server's default channel (new users land here).
    pub is_default: bool,
    /// Whether the channel is private (`channel_flag_private`).
    pub is_private: bool,
    /// Whether we are subscribed to this channel (we hear it).
    pub subscribed: bool,
    /// Channel icon id, 0 when the channel has none.
    pub icon_id: u32,
    /// Whether the channel's voice is transmitted unencrypted.
    pub is_unencrypted: bool,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct TsClient {
    pub id: u32,
    pub nickname: String,
    pub channel_id: u32,
    pub channel_group_id: u64,
    pub channel_group_name: Option<String>,
    /// Icon of the channel group, 0 when the group has none. Icons are
    /// downloaded lazily through the file-transfer channel.
    pub channel_group_icon_id: u32,
    pub server_group_ids: Vec<u64>,
    pub server_group_names: Vec<String>,
    /// Icons of the server groups, aligned with `server_group_names`.
    /// A 0 entry means that group has no icon.
    pub server_group_icon_ids: Vec<u32>,
    pub away: bool,
    pub input_muted: bool,
    pub output_muted: bool,
    pub is_talking: bool,
    pub is_whispering: bool,
    /// Bitmask of `ClientPermissionHint` sent by the server: what *we* are
    /// allowed to do to this client. 0 means "nothing / not yet known".
    pub permission_hints: u64,
    pub volume: f32,
    pub uid: Option<String>,
    /// Client type: 0 = normal user, 1 = server query (a bot/admin tool).
    pub client_type: u8,
    /// `client_talk_power`: how much talk power this client holds.
    pub talk_power: i32,
    /// Whether the client's talk power satisfies the channel's requirement.
    pub talk_power_granted: bool,
    /// Whether the client is recording the server (TTS / `client_recording`).
    pub is_priority_speaker: bool,
    /// Whether the client is the channel commander (server-granted icon).
    pub is_channel_commander: bool,
    /// `client_record`: whether the client is recording this channel.
    pub is_recording: bool,
    /// Capture / output hardware flags (distinct from the "muted" flags: a
    /// user can have input unmuted but hardware disabled, which the desktop
    /// client shows differently).
    pub input_hardware_enabled: bool,
    pub output_hardware_enabled: bool,
    /// `client_output_only_muted`: hears nothing but still transmits.
    pub output_only_muted: bool,
    /// Phonetic rendition of the nickname, when the server provides one.
    pub phonetic_name: String,
    /// ISO country code (e.g. "DE"), empty when unknown.
    pub country_code: String,
    /// Free-form `client_meta_data`, used by some community groups.
    pub metadata: String,
    /// MD5 of the avatar image, used to fetch it via the file-transfer channel.
    pub avatar_hash: String,
}

// ─── Per-client lock-free jitter buffer ──────────────────────────────

/// Lock-free per-client jitter buffer with 32 slots (640ms window at 20ms/frame).
/// Writer: decoding thread (one per client). Reader: cpal audio callback.
pub struct ClientJitterBuffer {
    /// Circular array of frame slots. AtomicCell swap provides lock-free read/write.
    pub slots: [AtomicCell<Option<Vec<i16>>>; 32],
    /// Sequence number of the most recently written frame (unwrapped to u32 space).
    pub write_seq: AtomicU32,
    /// First sequence number seen, unwrapped to u32 space. Set once with compare_exchange.
    pub base_seq: AtomicU32,
    /// Global play_slot at which base_seq should be played (base_seq → base_slot mapping).
    pub base_slot: AtomicU64,
    /// Monotonic timestamp of last received packet. None = never received. Used for cleanup.
    pub last_packet: AtomicCell<Option<Instant>>,
    /// Lock-free frame pool — callback pushes used frames, decoder pops them. No contention.
    pub frame_pool: SegQueue<Vec<i16>>,
    /// Linear gain as f32::to_bits, applied as mixing weight in the audio callback.
    pub volume: AtomicU32,
}

impl Default for ClientJitterBuffer {
    fn default() -> Self {
        Self::new()
    }
}

impl ClientJitterBuffer {
    pub fn new() -> Self {
        // Array-repeat initializer idiom: the const is expanded once per slot,
        // so no interior-mutable value is ever shared between slots.
        #[allow(clippy::declare_interior_mutable_const)]
        const NONE: AtomicCell<Option<Vec<i16>>> = AtomicCell::new(None);
        Self {
            slots: [NONE; 32],
            write_seq: AtomicU32::new(0),
            base_seq: AtomicU32::new(0),
            base_slot: AtomicU64::new(0),
            last_packet: AtomicCell::new(None),
            frame_pool: SegQueue::new(),
            volume: AtomicU32::new(f32::to_bits(1.0)),
        }
    }
}

// ─── Per-session connection state ────────────────────────────────────

pub struct TsConnection {
    pub connected: bool,
    pub connecting: bool,
    pub server_name: String,
    /// Stable server identity, see `TsEvent::Connected::server_uid`.
    pub server_uid: String,
    pub nickname: String,
    pub own_client_id: u32,
    pub channels: Vec<TsChannel>,
    pub clients: Vec<TsClient>,
    // Audio send state
    pub pcm_in: Vec<f32>,
    pub audio_encoder: Option<opus_rs::OpusEncoder>,
    pub audio_seq: u16,
    pub vad_threshold: f32,
    pub vad_enabled: bool,
    /// Adaptive ambient-noise estimate used by the hybrid volume/speech gate.
    pub vad_noise_floor: f32,
    pub vad_hold: u32,
    pub voice_active: bool,
    pub disconnect_requested: bool,
    pub mic_gain: f32,
    // Audio receive state
    pub talking_clients: HashMap<u16, Instant>, // last audio timestamp per client (monotonic Instant)
    pub whispering_clients: HashMap<u16, Instant>,
    /// Previous RTT sample, in ms, for jitter computation. 0 = no prior sample.
    pub last_rtt_ms: u64,
    /// EWMA of the inter-arrival jitter of the RTT. 0 until two samples arrive.
    pub jitter_ms: u64,
    /// Per-client permission hints from `notifyclientpermhints`, the same
    /// mechanism the desktop client uses to decide which context-menu entries
    /// exist for a given target.
    pub permission_hints: HashMap<u16, u64>,
    // Whisper state
    /// Outgoing whisper is armed. Voice frames are sent as `C2SWhisper`
    /// while this is set AND at least one target exists.
    pub whisper_active: bool,
    /// Whisper target client IDs (session-scoped handles, max 100).
    pub whisper_target_clients: Vec<u16>,
    /// Whisper target channel IDs (max 100).
    pub whisper_target_channels: Vec<u64>,
    /// Voice packet counter for whisper packets. TeamSpeak numbers voice and
    /// whisper packets independently, so the whisper stream keeps its own id.
    pub whisper_seq: u16,
    /// Whether the previous transmitted frame was a whisper frame. Used to
    /// emit a zero-length terminator when the stream type changes, which is
    /// how the official client signals "stopped talking".
    pub whisper_was_active: bool,
    /// 0 = accept every incoming whisper, 1 = only accept whispers from
    /// clients whose UID is in `whisper_allowed_uids`.
    pub whisper_allow_mode: u8,
    /// UIDs allowed to whisper this client when `whisper_allow_mode == 1`.
    pub whisper_allowed_uids: HashSet<String>,
    /// Number of incoming whisper frames dropped by the allow list since
    /// the last connect. Purely diagnostic, surfaced to the UI.
    pub whisper_ignored_count: u64,
    /// Buffers for an in-flight `ftgetfilelist` request, keyed by
    /// `(channel_id, path)`. Each `FileList` part appends one entry; the
    /// matching `FileListFinished` emits the assembled list and clears it.
    pub file_list_buffers: HashMap<(u64, String), Vec<TsServerFile>>,
}

impl TsConnection {
    pub fn new() -> Self {
        Self {
            connected: false,
            connecting: false,
            server_name: String::new(),
            server_uid: String::new(),
            nickname: String::new(),
            own_client_id: 0,
            channels: Vec::new(),
            clients: Vec::new(),
            pcm_in: Vec::new(),
            audio_encoder: None,
            audio_seq: 0,
            vad_threshold: 0.0,
            vad_enabled: false,
            vad_noise_floor: 0.0,
            vad_hold: 0,
            voice_active: false,
            disconnect_requested: false,
            mic_gain: 1.0,
            talking_clients: HashMap::new(),
            whispering_clients: HashMap::new(),
            last_rtt_ms: 0,
            jitter_ms: 0,
            permission_hints: HashMap::new(),
            whisper_active: false,
            whisper_target_clients: Vec::new(),
            whisper_target_channels: Vec::new(),
            whisper_seq: 0,
            whisper_was_active: false,
            whisper_allow_mode: 0,
            whisper_allowed_uids: HashSet::new(),
            whisper_ignored_count: 0,
            file_list_buffers: HashMap::new(),
        }
    }
}

impl Default for TsConnection {
    fn default() -> Self {
        Self::new()
    }
}

pub static PANIC_LOG: Lazy<Mutex<String>> = Lazy::new(|| Mutex::new(String::new()));

/// cpal output stream (Send-safe wrapper). Drop to stop audio playback.
pub struct SendStream(pub Option<cpal::Stream>);
unsafe impl Send for SendStream {}
pub static AUDIO_STREAM: std::sync::Mutex<SendStream> = std::sync::Mutex::new(SendStream(None));

// ─── Lock-free audio globals (namespaced per connection) ────────────

/// A unique audio source: server connection + session-scoped client handle.
pub type AudioKey = (ConnectionId, u16);

pub static CLIENT_BUFFERS: Lazy<DashMap<AudioKey, ClientJitterBuffer>> = Lazy::new(DashMap::new);
pub static AUDIO_DECODERS: Lazy<DashMap<AudioKey, opus_rs::OpusDecoder>> = Lazy::new(DashMap::new);
pub static AUDIO_DECODERS_STEREO: Lazy<DashMap<AudioKey, opus_rs::OpusDecoder>> =
    Lazy::new(DashMap::new);
pub const FRAME_SIZE: u64 = 960;
/// Total samples written to the hardware output buffer since stream start.
/// Logical frame number = PLAYED_SAMPLES / FRAME_SIZE.
pub static PLAYED_SAMPLES: Lazy<AtomicU64> = Lazy::new(|| AtomicU64::new(0));
/// Master output volume as a linear-gain value packed with `f32::to_bits`.
/// Applied as a final multiplier to the mix in the cpal callback, so one tap
/// changes the loudness of every server without touching per-client volume.
/// Default: unity (0 dB).
pub static MASTER_VOLUME: Lazy<AtomicU32> = Lazy::new(|| AtomicU32::new(f32::to_bits(1.0)));

pub fn master_volume_gain() -> f32 {
    f32::from_bits(MASTER_VOLUME.load(Ordering::Relaxed)).max(0.0)
}

/// Sets the master output volume from a dB value in [-20, +20].
pub fn set_master_volume_db(db: f32) {
    let db = db.clamp(-20.0, 20.0);
    let gain = 10.0f32.powf(db / 20.0);
    MASTER_VOLUME.store(f32::to_bits(gain), Ordering::Relaxed);
}
/// Client ID snapshot for the audio callback — avoids iterating DashMap in the callback.
/// Refreshed by the maintenance task every 500ms. Lock-free via ArcSwap.
/// Entries are `(connection_id, client_id)` so two servers can reuse the same
/// numeric client ID without their audio colliding.
pub static ACTIVE_CLIENT_IDS: Lazy<arc_swap::ArcSwap<Vec<AudioKey>>> =
    Lazy::new(|| arc_swap::ArcSwap::from(std::sync::Arc::new(Vec::new())));

// ─── Diagnostic callback stats (all atomics, safe to write from audio thread) ──

pub struct CallbackStats {
    /// Total callback invocations since last stats print.
    pub callbacks: AtomicU64,
    /// Sum of data.len() across all callbacks since last print.
    pub samples_total: AtomicU64,
    /// Total mix frames generated (slot changes) since last print.
    pub mix_frames: AtomicU64,
    /// DRIFT CHECK: expected played value at next callback entry. Set at end of
    /// each callback to (PLAYED_SAMPLES after fetch_add). The next callback compares
    /// its played_before against this value; mismatch = audio clock drift.
    pub expected_next_played: AtomicU64,
    /// Total PLAYED_SAMPLES consistency violations.
    pub played_mismatches: AtomicU64,
    /// Microseconds since the previous callback entry (0 if this is first).
    pub last_interval_us: AtomicU64,
    /// Instant::now() at the start of the last callback, in nanoseconds from boot.
    /// Used to compute the interval to the next callback.
    pub last_cb_entry_ns: AtomicU64,
}

pub static CB_STATS: Lazy<CallbackStats> = Lazy::new(|| CallbackStats {
    callbacks: AtomicU64::new(0),
    samples_total: AtomicU64::new(0),
    mix_frames: AtomicU64::new(0),
    expected_next_played: AtomicU64::new(0),
    played_mismatches: AtomicU64::new(0),
    last_interval_us: AtomicU64::new(0),
    last_cb_entry_ns: AtomicU64::new(0),
});

// ─── Logging ────────────────────────────────────────────────────────

/// Log verbosity, shared with Dart through `ts_set_log_level`.
/// 0 = off, 1 = error, 2 = warn, 3 = info, 4 = debug.
pub static LOG_LEVEL: Lazy<AtomicU32> = Lazy::new(|| {
    // Release builds stay at "warn": engine logs go to logcat, which is
    // readable from bug reports and by tooling on the device.
    AtomicU32::new(if cfg!(debug_assertions) { 4 } else { 2 })
});

pub const LOG_ERROR: u32 = 1;
pub const LOG_WARN: u32 = 2;
pub const LOG_INFO: u32 = 3;
pub const LOG_DEBUG: u32 = 4;

pub fn log_enabled(level: u32) -> bool {
    LOG_LEVEL.load(std::sync::atomic::Ordering::Relaxed) >= level
}

/// Redacts anything that identifies the user or the server.
///
/// The engine handles addresses, nicknames, UIDs and identity blobs; none of
/// them belong in logcat. Kept deliberately simple and allocation-light: it
/// only runs on messages that passed the level filter.
pub fn redact(message: &str) -> String {
    const PLACEHOLDER: &str = "<redacted>";
    /// Keys whose value is always secret, whatever it looks like.
    const SECRET_KEYS: [&str; 9] = [
        "password",
        "passwd",
        "pwd",
        "token",
        "secret",
        "identity",
        "client_identity",
        "uid",
        "nickname",
    ];

    fn looks_sensitive(value: &str) -> bool {
        let host = value.contains('.')
            && value.len() > 3
            && value
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || ".:-_".contains(c))
            && value.chars().any(|c| c.is_ascii_alphabetic() || c == ':');
        let blob = value.len() >= 24
            && value
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '+' || c == '/' || c == '=');
        host || blob
    }

    let mut out = String::with_capacity(message.len());
    for token in message.split_inclusive(char::is_whitespace) {
        let trimmed = token.trim_end();
        let whitespace = &token[trimmed.len()..];
        let core = trimmed.trim_matches(|c: char| "\"',;()[]{}".contains(c));
        let lead_len = trimmed.len()
            - trimmed
                .trim_start_matches(|c: char| "\"'([{".contains(c))
                .len();
        let (lead, tail) = trimmed.split_at(lead_len);
        let trail = &tail[core.len()..];

        // `key=value` / `key:value`: redact the value when the key is secret
        // or the value itself looks like an address or an identity blob.
        let separator = core.find(['=', ':']).filter(|index| {
            let key = &core[..*index];
            !key.is_empty() && key.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
        });
        let replacement = match separator {
            Some(index) => {
                let key = core[..index].to_ascii_lowercase();
                let value = &core[index + 1..];
                if SECRET_KEYS.contains(&key.as_str()) || looks_sensitive(value) {
                    Some(format!("{}={}", &core[..index], PLACEHOLDER))
                } else {
                    None
                }
            }
            None if looks_sensitive(core) => Some(PLACEHOLDER.to_string()),
            None => None,
        };

        out.push_str(lead);
        match replacement {
            Some(value) => out.push_str(&value),
            None => out.push_str(core),
        }
        out.push_str(trail);
        out.push_str(whitespace);
    }
    out
}

/// Level-filtered, redacted logging. Use instead of `eprintln!`.
#[macro_export]
macro_rules! ts_log {
    ($level:expr, $($arg:tt)*) => {{
        if $crate::log_enabled($level) {
            eprintln!("{}", $crate::redact(&format!($($arg)*)));
        }
    }};
}

#[macro_export]
macro_rules! log_error {
    ($($arg:tt)*) => { $crate::ts_log!($crate::LOG_ERROR, $($arg)*) };
}

#[macro_export]
macro_rules! log_warn {
    ($($arg:tt)*) => { $crate::ts_log!($crate::LOG_WARN, $($arg)*) };
}

#[macro_export]
macro_rules! log_info {
    ($($arg:tt)*) => { $crate::ts_log!($crate::LOG_INFO, $($arg)*) };
}

#[macro_export]
macro_rules! log_debug {
    ($($arg:tt)*) => { $crate::ts_log!($crate::LOG_DEBUG, $($arg)*) };
}

pub fn install_panic_hook() {
    std::panic::set_hook(Box::new(|info| {
        let location = info
            .location()
            .map(|l| {
                let file = l.file();
                let short = file.rsplit(&['/', '\\']).next().unwrap_or(file);
                format!("{}:{}:{}", short, l.line(), l.column())
            })
            .unwrap_or_else(|| "unknown location".into());
        let payload = if let Some(s) = info.payload().downcast_ref::<&str>() {
            s.to_string()
        } else if let Some(s) = info.payload().downcast_ref::<String>() {
            s.clone()
        } else {
            "unknown panic".into()
        };
        let msg = format!("PANIC {}: {}", location, payload);
        // Panics are always logged: they are the one thing worth a bug report.
        eprintln!("{}", redact(&msg));
        *PANIC_LOG.lock() = msg;
    }));
}

pub fn flush_panic_log() {
    let message = {
        let mut log = PANIC_LOG.lock();
        if log.is_empty() {
            return;
        }
        let message = log.clone();
        log.clear();
        message
    };
    push_global_event(TsEvent::Diag { msg: message });
}

/// Removes every audio artifact belonging to a session that is going away, so
/// its speakers stop contributing to the mix and its decoders are dropped.
pub fn drop_session_audio(connection_id: ConnectionId) {
    let keys: Vec<AudioKey> = CLIENT_BUFFERS
        .iter()
        .map(|e| *e.key())
        .filter(|(cid, _)| *cid == connection_id)
        .collect();
    for key in keys {
        if let Some((_, buf)) = CLIENT_BUFFERS.remove(&key) {
            for slot in &buf.slots {
                if let Some(frame) = slot.swap(None) {
                    buf.frame_pool.push(frame);
                }
            }
        }
        AUDIO_DECODERS.remove(&key);
        AUDIO_DECODERS_STEREO.remove(&key);
    }
    refresh_active_client_snapshot();
}

/// Rebuilds the (connection_id, client_id) snapshot read by the audio callback.
pub fn refresh_active_client_snapshot() {
    let ids: Vec<AudioKey> = CLIENT_BUFFERS.iter().map(|e| *e.key()).collect();
    ACTIVE_CLIENT_IDS.store(std::sync::Arc::new(ids));
}
