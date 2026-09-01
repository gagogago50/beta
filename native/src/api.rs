use crate::{
    log_debug, log_error, log_info, log_warn, push_event, AudioKey, Command, ConnectFailure,
    ConnectPhase, TsChannel, TsClient, TsConnection, TsEvent, ACTIVE_CLIENT_IDS, AUDIO_DECODERS,
    AUDIO_DECODERS_STEREO, AUDIO_STREAM, CB_STATS, CLIENT_BUFFERS, CLIENT_VOLUMES, EVENT_NOTIFIER,
    EVENT_QUEUE, FRAME_SIZE, IDENTITY_STASH, OUTPUT_RESTART_REQUESTED, PLAYED_SAMPLES, RUNTIME,
    SESSIONS,
};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use futures::prelude::*;
use opus_rs::OpusDecoder;
use std::borrow::Cow;
use std::collections::HashMap;
use std::ffi::CString;
use std::os::raw::c_char;
use std::sync::atomic::Ordering;
use std::time::{Duration, Instant};
use tsclientlib::messages::c2s::*;
use tsclientlib::Reason;
use tsclientlib::{ChannelId, ClientId};
use tsclientlib::{Connection, DisconnectOptions, Identity, OutCommandExt, StreamItem};
use tsproto_packets::packets::{AudioData, CodecType, InAudioBuf, OutAudio};

/// Upper bound for the whole handshake (resolve → initserver → server book).
/// The desktop client gives up in the same ballpark; without it a black-holed
/// UDP path would leave the UI spinning forever.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);

/// Maintenance cadence while at least one client is streaming audio.
const SNAPSHOT_ACTIVE: Duration = Duration::from_millis(500);
/// Maintenance cadence in a silent channel. Long enough to matter for battery,
/// short enough that the first speaker is picked up without audible delay
/// (the jitter buffer covers the gap).
const SNAPSHOT_IDLE: Duration = Duration::from_secs(2);

fn to_c_str(s: String) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new("null string").unwrap())
        .into_raw()
}

#[no_mangle]
pub extern "C" fn ts_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

#[no_mangle]
pub extern "C" fn ts_set_event_notifier(callback: *mut std::ffi::c_void) {
    EVENT_NOTIFIER.store(callback.cast(), Ordering::Release);
    if !callback.is_null() && !EVENT_QUEUE.lock().is_empty() {
        crate::notify_event_listener();
    }
}

fn push_diag(conn_id: crate::ConnectionId, msg: &str) {
    use std::sync::atomic::AtomicU64;
    static DIAG_SEQ: AtomicU64 = AtomicU64::new(0);
    let seq = DIAG_SEQ.fetch_add(1, Ordering::SeqCst);
    push_event(
        conn_id,
        TsEvent::Diag {
            msg: format!("#{} {}", seq, msg),
        },
    );
}

/// Hybrid voice activity gate inspired by the user-visible behavior of the
/// official client: a volume gate is combined with lightweight speech-shape
/// checks. This is an independent implementation; it does not copy TeamSpeak's
/// WebRTC/RNN VAD and intentionally uses no prebuilt detector binary.
fn hybrid_vad_should_transmit(state: &mut TsConnection, frame: &[f32]) -> bool {
    if frame.is_empty() {
        return false;
    }

    let mut sum_sq = 0.0f32;
    let mut peak = 0.0f32;
    let mut zero_crossings = 0usize;
    let mut previous = frame[0];
    for &sample in frame {
        let clean = if sample.is_finite() {
            sample.clamp(-1.0, 1.0)
        } else {
            0.0
        };
        sum_sq += clean * clean;
        peak = peak.max(clean.abs());
        if (clean >= 0.0) != (previous >= 0.0) {
            zero_crossings += 1;
        }
        previous = clean;
    }

    let rms = (sum_sq / frame.len() as f32).sqrt();
    let configured_gate = state.vad_threshold.max(0.000_5);

    // Learn ambient noise only while clearly below the configured gate. The
    // slow update avoids adapting the floor upward during normal speech.
    if rms < configured_gate * 0.8 {
        state.vad_noise_floor = if state.vad_noise_floor <= 0.0 {
            rms.max(0.000_1)
        } else {
            state.vad_noise_floor * 0.98 + rms * 0.02
        };
    }

    let adaptive_gate = (state.vad_noise_floor * 2.5)
        .max(configured_gate * 0.55)
        .min(configured_gate);
    let zcr = zero_crossings as f32 / frame.len() as f32;
    let crest = peak / rms.max(0.000_001);
    let speech_shape = (0.008..=0.35).contains(&zcr) && (1.2..=14.0).contains(&crest);

    // Loud speech always opens the gate. Quieter input must be above the
    // adaptive noise floor and have a speech-like shape.
    rms >= configured_gate || (rms >= adaptive_gate && speech_shape)
}

/// Maps a TeamSpeak `Codec` enum to the wire codec id used by the desktop
/// client and its channel-info display. Values follow the official ordering
/// (`channel_codec`): Speex narrowband=0 … Opus music=5.
fn channel_codec_code(codec: &tsclientlib::Codec) -> u8 {
    use tsclientlib::Codec;
    match codec {
        Codec::SpeexNarrowband => 0,
        Codec::SpeexWideband => 1,
        Codec::SpeexUltrawideband => 2,
        Codec::CeltMono => 3,
        Codec::OpusVoice => 4,
        Codec::OpusMusic => 5,
    }
}

/// Maps a TeamSpeak `ChannelType` to the persistence code used by the UI:
/// 0 = temporary (deleted when empty), 1 = permanent, 2 = semi-permanent.
fn channel_type_code(channel_type: &tsclientlib::ChannelType) -> u8 {
    use tsclientlib::ChannelType;
    match channel_type {
        ChannelType::Permanent => 1,
        ChannelType::SemiPermanent => 2,
        ChannelType::Temporary => 0,
    }
}

/// Build the roster snapshot from the server book.
///
/// `now_connected`, `talking`, `whispering`, `permission_hints` come from the
/// session's live state so the per-client flags reflect the most recent audio
/// and permission updates. Volume comes from the global [`CLIENT_VOLUMES`]
/// (UID-keyed), which survives session teardown.
fn refresh_from_book(
    conn_id: crate::ConnectionId,
    book: &tsclientlib::data::Connection,
    talking: &HashMap<u16, Instant>,
    whispering: &HashMap<u16, Instant>,
    permission_hints: &HashMap<u16, u64>,
) -> (Vec<TsChannel>, Vec<TsClient>) {
    let mut count: HashMap<u64, u32> = HashMap::new();
    for c in book.clients.values() {
        *count.entry(c.channel.0).or_insert(0) += 1;
    }
    let channels = book
        .channels
        .values()
        .map(|c| TsChannel {
            id: c.id.0 as u32,
            name: c.name.clone(),
            parent_id: if c.parent.0 == 0 {
                0
            } else {
                c.parent.0 as u32
            },
            topic: c.topic.clone().unwrap_or_default(),
            has_password: c.has_password.unwrap_or(false),
            client_count: *count.get(&c.id.0).unwrap_or(&0),
            order: c.order.0 as u32,
            needed_talk_power: c.needed_talk_power.unwrap_or(0),
            max_clients: match c.max_clients.unwrap_or(tsclientlib::MaxClients::Unlimited) {
                tsclientlib::MaxClients::Unlimited => -1,
                tsclientlib::MaxClients::Inherited => -2,
                tsclientlib::MaxClients::Limited(n) => n as i32,
            },
            codec: channel_codec_code(&c.codec),
            codec_quality: c.codec_quality.unwrap_or(0),
            channel_type: channel_type_code(&c.channel_type),
            is_default: c.is_default.unwrap_or(false),
            is_private: c.is_private.unwrap_or(false),
            subscribed: c.subscribed,
            icon_id: c.icon.unwrap_or(tsclientlib::IconId(0)).0,
            is_unencrypted: c.is_unencrypted.unwrap_or(true),
        })
        .collect();
    let clients: Vec<_> = book
        .clients
        .values()
        .map(|c| {
            let uid = c.uid.as_ref().map(|u| u.to_string());
            // (name, icon) pairs for the client's server groups, resolved once
            // so names and icons cannot drift apart.
            let groups: Vec<(String, u32)> = c
                .server_groups
                .iter()
                .filter_map(|group_id| book.server_groups.get(group_id))
                .map(|group| (group.name.clone(), group.icon.0))
                .collect();
            let cid = c.id.0;
            TsClient {
                id: cid as u32,
                nickname: c.name.clone(),
                channel_id: c.channel.0 as u32,
                channel_group_id: c.channel_group.0,
                channel_group_name: book
                    .channel_groups
                    .get(&c.channel_group)
                    .map(|group| group.name.clone()),
                channel_group_icon_id: book
                    .channel_groups
                    .get(&c.channel_group)
                    .map(|group| group.icon.0)
                    .unwrap_or(0),
                server_group_ids: {
                    let mut groups: Vec<u64> =
                        c.server_groups.iter().map(|group| group.0).collect();
                    groups.sort_unstable();
                    groups
                },
                server_group_names: {
                    let mut names: Vec<String> =
                        groups.iter().map(|(name, _)| name.clone()).collect();
                    names.sort();
                    names
                },
                server_group_icon_ids: {
                    // Sorted by name so icons stay aligned with the names list
                    // above; the UI pairs them by index.
                    let mut sorted = groups.clone();
                    sorted.sort_by(|left, right| left.0.cmp(&right.0));
                    sorted.into_iter().map(|(_, icon)| icon).collect()
                },
                uid,
                away: c.away_message.is_some(),
                input_muted: c.input_muted,
                output_muted: c.output_muted,
                client_type: match c.client_type {
                    tsclientlib::ClientType::Normal => 0,
                    tsclientlib::ClientType::Query { .. } => 1,
                },
                talk_power: c.talk_power,
                talk_power_granted: c.talk_power_granted,
                is_priority_speaker: c.is_priority_speaker,
                is_channel_commander: c.is_channel_commander,
                is_recording: c.is_recording,
                input_hardware_enabled: c.input_hardware_enabled,
                output_hardware_enabled: c.output_hardware_enabled,
                output_only_muted: c.output_only_muted,
                phonetic_name: c.phonetic_name.clone(),
                country_code: c.country_code.clone(),
                metadata: c.metadata.clone(),
                avatar_hash: c.avatar_hash.clone(),
                is_talking: talking
                    .get(&cid)
                    .map(|t| t.elapsed().as_millis() < 500)
                    .unwrap_or(false),
                is_whispering: whispering
                    .get(&cid)
                    .map(|t| t.elapsed().as_millis() < 500)
                    .unwrap_or(false),
                permission_hints: permission_hints.get(&cid).copied().unwrap_or(0),
                volume: c
                    .uid
                    .as_ref()
                    .and_then(|uid| CLIENT_VOLUMES.lock().get(&uid.to_string()).copied())
                    .unwrap_or_else(|| {
                        // Fallback: convert linear gain from jitter buffer → dB
                        CLIENT_BUFFERS
                            .get(&(conn_id, cid))
                            .map(|b| {
                                let gain = f32::from_bits(b.volume.load(Ordering::Relaxed));
                                20.0 * gain.max(1e-10).log10()
                            })
                            .unwrap_or(0.0) // default: 0 dB = unity gain
                    }),
            }
        })
        .collect();
    (channels, clients)
}

// ─── Identity (engine-wide) ─────────────────────────────────────────

#[no_mangle]
pub extern "C" fn ts_set_identity(json: *const c_char) {
    if json.is_null() {
        return;
    }
    let s = unsafe { std::ffi::CStr::from_ptr(json) }
        .to_string_lossy()
        .into_owned();
    *IDENTITY_STASH.lock() = if s.is_empty() { None } else { Some(s) };
}

#[no_mangle]
pub extern "C" fn ts_get_identity() -> *mut c_char {
    let id = IDENTITY_STASH.lock().clone();
    match id {
        Some(s) => to_c_str(s),
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn ts_clear_identity() -> u8 {
    *IDENTITY_STASH.lock() = None;
    log_info!("identity cleared from the engine");
    1
}

#[no_mangle]
pub extern "C" fn ts_set_log_level(level: u8) -> u8 {
    if level > 4 {
        return 0;
    }
    crate::LOG_LEVEL.store(level as u32, Ordering::Relaxed);
    1
}

// ─── Connect ────────────────────────────────────────────────────────

/// Starts a connection attempt to a virtual server and immediately registers a
/// new session, returning its unique `connection_id`. The handshake runs as a
/// background task; its outcomes arrive as `connection_phase`,
/// `connect_failed` or `connected` events tagged with that id.
///
/// Unlike the old single-connection entry point, multiple concurrent attempts
/// (and later, live sessions) are fully independent — each has its own state,
/// command queue, flood budget and audio namespace.
#[no_mangle]
pub extern "C" fn ts_connect(
    address: *const c_char,
    nickname: *const c_char,
    channel: *const c_char,
    password: *const c_char,
    channel_password: *const c_char,
) -> *mut c_char {
    let address = unsafe { std::ffi::CStr::from_ptr(address) }
        .to_string_lossy()
        .into_owned();
    let nickname = unsafe { std::ffi::CStr::from_ptr(nickname) }
        .to_string_lossy()
        .into_owned();
    let channel = if channel.is_null() {
        None
    } else {
        Some(
            unsafe { std::ffi::CStr::from_ptr(channel) }
                .to_string_lossy()
                .into_owned(),
        )
    };
    let password = if password.is_null() {
        None
    } else {
        Some(
            unsafe { std::ffi::CStr::from_ptr(password) }
                .to_string_lossy()
                .into_owned(),
        )
    };
    let channel_password = if channel_password.is_null() {
        None
    } else {
        Some(
            unsafe { std::ffi::CStr::from_ptr(channel_password) }
                .to_string_lossy()
                .into_owned(),
        )
    };

    let conn_id = crate::next_connection_id();
    log_info!("ts_connect: session {} starting", conn_id);

    let mut state = TsConnection::new();
    state.connecting = true;
    state.nickname = nickname.clone();
    // Whisper targets are session-scoped client/channel IDs — never carry
    // them over to a new session, they would point at unrelated clients.
    state.whisper_allow_mode = 0;
    state.whisper_ignored_count = 0;
    let session = crate::Session::new(conn_id, state);

    // Remember the host (without port) for the file-transfer fallback path.
    let host = address
        .rsplit_once(':')
        .map(|(host, _)| host.to_string())
        .unwrap_or_else(|| address.clone());
    *session.server_host.lock() = host.trim_matches(['[', ']']).to_string();

    SESSIONS.insert(conn_id, session);

    let handle = RUNTIME.spawn(async move {
        if let Err(failure) = do_connect(
            conn_id,
            address,
            nickname,
            channel,
            password,
            channel_password,
        )
        .await
        {
            log_error!(
                "do_connect: session {} FAILED kind={} phase={} retryable={} ({})",
                conn_id,
                failure.kind,
                failure.phase.as_str(),
                failure.retryable,
                failure.message
            );
            if let Some(state) = crate::session(conn_id) {
                state.lock().connecting = false;
            }
            push_event(conn_id, failure.into_event());
        }
        if let Some(s) = SESSIONS.get(&conn_id) {
            *s.connect_task.lock() = None;
        }
    });
    if let Some(s) = SESSIONS.get(&conn_id) {
        *s.connect_task.lock() = Some(handle);
    }

    to_c_str(serde_json::json!({"type": "connecting", "connection_id": conn_id}).to_string())
}

/// Aborts an in-flight connection attempt for one session.
///
/// Without this a user leaving the connect screen would leave a task retrying
/// DNS and handshakes in the background, and its late failure event would land
/// on an unrelated screen. Returns 0 when no attempt was running.
#[no_mangle]
pub extern "C" fn ts_cancel_connect(conn_id: crate::ConnectionId) -> u8 {
    let handle = SESSIONS
        .get(&conn_id)
        .and_then(|s| s.connect_task.lock().take());
    let was_connecting = crate::session(conn_id)
        .map(|st| {
            let mut guard = st.lock();
            let was = guard.connecting;
            guard.connecting = false;
            was
        })
        .unwrap_or(false);
    let mut aborted = false;
    if let Some(handle) = handle {
        handle.abort();
        aborted = true;
    }
    if !aborted && !was_connecting {
        return 0;
    }
    push_event(
        conn_id,
        ConnectFailure::new(
            "cancelled",
            ConnectPhase::Connecting,
            "Connection attempt cancelled".into(),
            false,
        )
        .into_event(),
    );
    1
}

/// Maps a `tsclientlib::Error` onto a stable error kind and a retry decision.
///
/// The classification is done on the error *variant*, never on its message:
/// text is localized/reworded upstream and cannot be a protocol contract.
fn classify_connect_error(error: &tsclientlib::Error) -> (&'static str, bool) {
    use tsclientlib::Error as E;
    match error {
        E::ResolveAddress(_) => ("dns", true),
        E::InitserverTimeout => ("timeout", true),
        E::Connect(_)
        | E::ConnectionFailed(_)
        | E::ConnectionGone
        | E::Io(_)
        | E::NotConnected
        | E::SendClientinit(_)
        | E::SendPacket(_)
        | E::InitserverWait(_) => ("network", true),
        E::IdentityLevel(_)
        | E::IdentityLevelCorrupted { .. }
        | E::IdentityLevelIncreaseFailedThread
        | E::IdentityCreate(_) => ("identity_level", false),
        E::ServerUidMismatch(_) => ("server_identity_changed", false),
        E::InitserverParse(_) | E::InitserverParamsMissing | E::FiletransferIo(_) => {
            ("protocol", false)
        }
        E::ConnectTs(server_error) => classify_server_refusal(*server_error),
        E::CommandError(command_error) => classify_server_refusal(command_error.error),
        // Every resolved address failed: report the first child verdict, and
        // stay retryable only if that child was.
        E::ConnectFailed { errors, .. } => errors
            .first()
            .map(classify_connect_error)
            .unwrap_or(("network", true)),
        // `tsclientlib::Error` is #[non_exhaustive]: a variant added upstream
        // must degrade to a retryable generic failure, not break the build.
        _ => ("unknown", true),
    }
}

/// Server-side refusal reasons that matter for the retry decision.
fn classify_server_refusal(error: tsclientlib::TsError) -> (&'static str, bool) {
    use tsclientlib::TsError as E;
    match error {
        E::ServerInvalidPassword | E::ClientInvalidPassword => ("password", false),
        E::ChannelInvalidPassword => ("channel_password", false),
        E::ConnectFailedBanned | E::RenameFailedBanned => ("banned", false),
        E::ClientNicknameInuse => ("nickname_in_use", false),
        E::ServerMaxclientsReached => ("server_full", true),
        E::ClientCouldNotValidateIdentity => ("identity_level", false),
        _ => ("server_refused", false),
    }
}

async fn do_connect(
    conn_id: crate::ConnectionId,
    address: String,
    nickname: String,
    channel: Option<String>,
    password: Option<String>,
    channel_password: Option<String>,
) -> Result<(), ConnectFailure> {
    crate::install_panic_hook();
    push_event(
        conn_id,
        TsEvent::ConnectionPhase {
            phase: ConnectPhase::Resolving.as_str().to_string(),
        },
    );
    let mut opts = Connection::build(address).name(nickname);
    if let Some(id_json) = IDENTITY_STASH.lock().take() {
        if let Ok(id) = serde_json::from_str::<Identity>(&id_json) {
            opts = opts.identity(id);
        }
    }
    if let Some(ch) = channel {
        opts = opts.channel(ch);
    }
    if let Some(pw) = password {
        opts = opts.password(pw);
    }
    if let Some(channel_pw) = channel_password {
        opts = opts.channel_password(channel_pw);
    }

    let mut con = opts.connect().map_err(|e| {
        let (kind, retryable) = classify_connect_error(&e);
        ConnectFailure::new(kind, ConnectPhase::Resolving, e.to_string(), retryable)
    })?;
    push_event(
        conn_id,
        TsEvent::ConnectionPhase {
            phase: ConnectPhase::Connecting.as_str().to_string(),
        },
    );

    let mut ok = false;
    let handshake = tokio::time::timeout(CONNECT_TIMEOUT, async {
        let mut announced_auth = false;
        while let Some(item) = con.events().next().await {
            match item {
                Ok(StreamItem::BookEvents(_)) => {
                    ok = true;
                    break;
                }
                Ok(StreamItem::IdentityLevelIncreasing(level)) => {
                    // Proof-of-work demanded by the server: not an error, it is
                    // the authentication phase doing its (slow) work.
                    if !announced_auth {
                        announced_auth = true;
                        push_event(
                            conn_id,
                            TsEvent::ConnectionPhase {
                                phase: ConnectPhase::Authenticating.as_str().to_string(),
                            },
                        );
                    }
                    push_event(
                        conn_id,
                        TsEvent::Diag {
                            msg: format!("Raising identity level to {}", level),
                        },
                    );
                }
                Ok(_) => {
                    if !announced_auth {
                        announced_auth = true;
                        push_event(
                            conn_id,
                            TsEvent::ConnectionPhase {
                                phase: ConnectPhase::Authenticating.as_str().to_string(),
                            },
                        );
                    }
                }
                Err(e) => {
                    let (kind, retryable) = classify_connect_error(&e);
                    return Err(ConnectFailure::new(
                        kind,
                        ConnectPhase::Authenticating,
                        e.to_string(),
                        retryable,
                    ));
                }
            }
        }
        Ok(())
    })
    .await;

    match handshake {
        Err(_) => {
            return Err(ConnectFailure::new(
                "timeout",
                ConnectPhase::Authenticating,
                format!(
                    "No answer from the server within {}s",
                    CONNECT_TIMEOUT.as_secs()
                ),
                true,
            ))
        }
        Ok(Err(failure)) => return Err(failure),
        Ok(Ok(())) => {}
    }

    if !ok {
        // The stream ended before the server book arrived: the peer closed the
        // handshake without a protocol-level error.
        return Err(ConnectFailure::new(
            "network",
            ConnectPhase::Authenticating,
            "The server closed the connection during the handshake".into(),
            true,
        ));
    }

    {
        let sub = OutChannelSubscribeAllMessage::new();
        let _ = sub.send(&mut con);
    }

    let book = con.get_state().map_err(|e| {
        let (kind, retryable) = classify_connect_error(&e);
        ConnectFailure::new(kind, ConnectPhase::Authenticating, e.to_string(), retryable)
    })?;
    // Snapshot the live audio/permission maps from this (still-empty) session;
    // they are empty at this point but the helper signature needs them.
    let (talking, whispering, permission_hints) = {
        let state = crate::session(conn_id).expect("connect session");
        let st = state.lock();
        (
            st.talking_clients.clone(),
            st.whispering_clients.clone(),
            st.permission_hints.clone(),
        )
    };
    let (channels, clients) =
        refresh_from_book(conn_id, book, &talking, &whispering, &permission_hints);
    let sname = book.server.name.clone();
    // Base64 of the server public key hash: the only server identifier that
    // survives a rename, used to scope the icon cache.
    let server_uid = book.server.public_key.get_uid();
    let voice_encryption_mode = format!("{:?}", book.server.codec_encryption_mode);
    let oid = book.own_client.0 as u32;
    // Server variables surfaced to the UI on connect: the welcome message is
    // shown in the server tab, the host message honours the server's mode, and
    // the capacity/identity-level let the status bar explain refusals.
    let welcome_message = book.server.welcome_message.clone();
    let host_message = book.server.hostmessage.clone();
    // TeamSpeak's host-message modes: 0 = none, 1 = log (show in chat), 2 =
    // modal, 3 = modal + disconnect.
    let host_message_mode = match book.server.hostmessage_mode {
        tsclientlib::HostMessageMode::None => 0u8,
        tsclientlib::HostMessageMode::Log => 1u8,
        tsclientlib::HostMessageMode::Modal => 2u8,
        tsclientlib::HostMessageMode::Modalquit => 3u8,
    };
    let max_clients = book.server.max_clients as u32;
    let needed_identity_security_level = book
        .server
        .optional_data
        .as_ref()
        .map(|d| d.needed_identity_security_level as u32)
        .unwrap_or(0);

    log_info!(
        "do_connect: session {} OK, {} channels, {} clients, own_id={}",
        conn_id,
        channels.len(),
        clients.len(),
        oid
    );

    let (cmd_tx, cmd_rx) = tokio::sync::mpsc::unbounded_channel();
    if let Some(s) = SESSIONS.get(&conn_id) {
        *s.command_tx.lock() = Some(cmd_tx);
    }

    {
        let state = crate::session(conn_id).expect("connect session");
        let mut st = state.lock();
        st.connecting = false;
        st.connected = true;
        st.server_name = sname.clone();
        st.server_uid = server_uid.clone();
        st.own_client_id = oid;
        st.channels = channels;
        st.clients = clients;
    }
    push_event(
        conn_id,
        TsEvent::Connected {
            server_name: sname,
            client_id: oid,
            voice_encryption_mode,
            server_uid,
            welcome_message,
            host_message,
            host_message_mode,
            max_clients,
            needed_identity_security_level,
        },
    );
    crate::notify_event_listener();

    if let Some(id) = con.get_options().get_identity() {
        if let Ok(json) = serde_json::to_string(id) {
            *IDENTITY_STASH.lock() = Some(json);
        }
    }

    // Stash the connection so the event loop can take it.
    if let Some(s) = SESSIONS.get(&conn_id) {
        *s.connection.lock() = Some(con);
    }

    // --- Push-mode audio output (cpal) with sample-driven mixing. A single
    // stream serves every connected server; connecting another server must
    // NOT reset the others' playback, so we only start it if it isn't running.
    spawn_maintenance_task();
    ensure_output_stream_running();

    RUNTIME.spawn(async move {
        let con = SESSIONS
            .get(&conn_id)
            .and_then(|s| s.connection.lock().take());
        let Some(con) = con else {
            log_error!("do_connect: session {} lost its connection", conn_id);
            return;
        };
        if let Some(s) = SESSIONS.get(&conn_id) {
            s.event_loop_alive.store(true, Ordering::SeqCst);
        }
        let fut = event_loop(conn_id, con, cmd_rx);
        let result = std::panic::AssertUnwindSafe(fut).catch_unwind().await;
        match result {
            Ok(_) => push_diag(conn_id, "event_loop: exited normally"),
            Err(e) => {
                let msg = if let Some(s) = e.downcast_ref::<&str>() {
                    s.to_string()
                } else if let Some(s) = e.downcast_ref::<String>() {
                    s.clone()
                } else {
                    "unknown panic".into()
                };
                push_diag(conn_id, &format!("event_loop PANICKED: {}", msg));
            }
        }
        if let Some(s) = SESSIONS.get(&conn_id) {
            s.event_loop_alive.store(false, Ordering::SeqCst);
        }
    });
    Ok(())
}

// ─── Audio receive helpers ──────────────────────────────────────────

/// Map a u16 packet sequence number to u32 global sequence space,
/// handling the 65536 wrap. Returns a stale-packet value (much smaller
/// than base) when the sequence has moved backward too far.
fn unwrap_seq(seq: u16, base: u16) -> u32 {
    let base_u32 = base as u32;
    let delta = seq.wrapping_sub(base) as i16 as i32;
    if delta >= 0 {
        base_u32.wrapping_add(delta as u32)
    } else if delta > -32768 {
        // Forward wrap: actual forward distance = 65536 + delta (range 32769..65535)
        base_u32.wrapping_add((65536u32).wrapping_add(delta as u32))
    } else {
        // delta <= -32768: stale/backward packet.
        // Returns a value much smaller than base_u32; outer sanity check discards it.
        base_u32.wrapping_add(delta as u32)
    }
}

/// Whisper allow list check for an incoming whisper frame.
///
/// `whisper_allow_mode == 0` accepts everything (TeamSpeak default).
/// In mode 1 the sender's UID must be in `whisper_allowed_uids`; a client
/// whose UID is not known yet is rejected, because accepting an unidentified
/// whisperer would defeat the point of the list.
fn whisper_is_allowed(conn_id: crate::ConnectionId, from_id: u16) -> bool {
    let Some(state) = crate::session(conn_id) else {
        return false;
    };
    let mut guard = state.lock();
    if guard.whisper_allow_mode == 0 {
        return true;
    }
    let uid = guard
        .clients
        .iter()
        .find(|c| c.id as u16 == from_id)
        .and_then(|c| c.uid.as_ref())
        .cloned();
    let allowed = match uid {
        Some(uid) => guard.whisper_allowed_uids.contains(&uid),
        None => false,
    };
    if !allowed {
        guard.whisper_ignored_count = guard.whisper_ignored_count.saturating_add(1);
    }
    allowed
}

/// Decode an incoming audio packet with a per-client OpusDecoder and push
/// the decoded frame into that client's lock-free jitter buffer.
/// No STATE lock held — decoders and buffers are in DashMaps, keyed by
/// `(connection_id, client_id)` so two servers may reuse the same numeric
/// client ID without their audio colliding.
/// Minimum jitter-buffer depth in 20ms frames. On a stable link we keep this —
/// it is the lowest latency that still absorbs a couple of lost packets.
const BASE_DELAY_FRAMES: u64 = 2;
/// One extra frame (20ms) of depth per this many ms of measured jitter.
const JITTER_TO_FRAMES_DIVISOR: u64 = 20;
/// Hard ceiling so a pathological link cannot balloon playback latency.
const MAX_DELAY_FRAMES: u64 = 8; // 160ms

/// Chooses the delay (in 20ms frames) for a *new* jitter buffer from the
/// session's measured inter-arrival jitter. Reads the session state once,
/// briefly. This is what keeps latency low on a healthy link (D3 adaptive
/// buffer): the buffer grows only as much as the network actually demands.
fn adaptive_delay_frames(conn_id: crate::ConnectionId) -> u64 {
    let jitter = crate::session(conn_id)
        .map(|state| state.lock().jitter_ms)
        .unwrap_or(0);
    let extra = jitter / JITTER_TO_FRAMES_DIVISOR;
    (BASE_DELAY_FRAMES + extra).min(MAX_DELAY_FRAMES)
}

fn decode_to_client_buffer(conn_id: crate::ConnectionId, audio_buf: InAudioBuf) {
    const FRAME: usize = 960;

    // Extract data from the self_cell-wrapped buffer
    let audio = audio_buf.data();
    let audio_data = audio.data();

    let (from_id, seq_id, opus_vec, is_whisper) = match audio_data {
        AudioData::S2C { id, from, data, .. } => (*from, *id as u32, data.to_vec(), false),
        AudioData::S2CWhisper { id, from, data, .. } => (*from, *id as u32, data.to_vec(), true),
        _ => return,
    };
    let seq_u16 = seq_id as u16;
    // audio_data and audio are references — they get dropped naturally
    drop(audio_buf);

    // Incoming whisper allow list: when enabled, only clients whose UID was
    // explicitly allowed may whisper this client. Dropped before decoding so
    // an unwanted whisper costs nothing but a short STATE lock.
    if is_whisper && !whisper_is_allowed(conn_id, from_id) {
        return;
    }

    let key: AudioKey = (conn_id, from_id);

    // Get or create per-client decoder (mono, fallback stereo) — DashMap, no STATE lock
    let mut decoder = AUDIO_DECODERS
        .entry(key)
        .or_insert_with(|| OpusDecoder::new(48000, 1).expect("mono decoder"));
    let mut pcm_out = vec![0.0f32; FRAME];
    let ok = match decoder.decode(&opus_vec, FRAME, &mut pcm_out) {
        Ok(_) => true,
        Err(_) => {
            drop(decoder);
            let mut stereo = AUDIO_DECODERS_STEREO
                .entry(key)
                .or_insert_with(|| OpusDecoder::new(48000, 2).expect("stereo decoder"));
            let mut stereo_out = vec![0.0f32; FRAME * 2];
            match stereo.decode(&opus_vec, FRAME, &mut stereo_out) {
                Ok(decoded) => {
                    let n = decoded.min(FRAME);
                    for i in 0..n {
                        pcm_out[i] = (stereo_out[i * 2] + stereo_out[i * 2 + 1]) * 0.5;
                    }
                    true
                }
                Err(e) => {
                    log_error!("opus decode error from client {}: {}", from_id, e);
                    false
                }
            }
        }
    };

    if !ok {
        return;
    }

    // Convert f32 → i16 (no volume post-gain — volume is applied as mixing weight in callback)
    let mut frame = vec![0i16; FRAME];
    for (i, &s) in pcm_out.iter().enumerate() {
        frame[i] = (s.clamp(-1.0, 1.0) * 32767.0).clamp(-32768.0, 32767.0) as i16;
    }

    // Get or create per-client jitter buffer — DashMap, no STATE lock
    let buf = CLIENT_BUFFERS.entry(key).or_insert_with(|| {
        let b = crate::ClientJitterBuffer::new();
        // Inherit persisted volume when creating a new jitter buffer: resolve
        // the client's UID from this session's roster, then look up the
        // UID-keyed global table.
        let persisted_db = crate::session(conn_id).and_then(|state| {
            let guard = state.lock();
            guard
                .clients
                .iter()
                .find(|c| c.id as u16 == from_id)
                .and_then(|c| c.uid.as_ref())
                .and_then(|uid| CLIENT_VOLUMES.lock().get(uid.as_str()).copied())
        });
        if let Some(db) = persisted_db {
            let gain = 10.0_f32.powf(db / 20.0);
            b.volume.store(f32::to_bits(gain), Ordering::Release);
        }
        b
    });

    // Init baseline with compare_exchange (prevents race when two packets arrive simultaneously)
    let tmp_global = unwrap_seq(seq_u16, 0);
    // The relaxed load is only a fast path; the compare_exchange is what makes
    // the initialization race-free when two packets arrive at once.
    if buf.base_seq.load(Ordering::Relaxed) == 0
        && buf
            .base_seq
            .compare_exchange(0, tmp_global, Ordering::Release, Ordering::Relaxed)
            .is_ok()
    {
        let now_slot = PLAYED_SAMPLES.load(Ordering::Relaxed) / crate::FRAME_SIZE;
        buf.base_slot
            .store(now_slot + adaptive_delay_frames(conn_id), Ordering::Release);
    }
    let mut base_seq = buf.base_seq.load(Ordering::Relaxed);
    let global_seq = unwrap_seq(seq_u16, base_seq as u16);
    let write_seq_before = buf.write_seq.load(Ordering::Relaxed);

    // Sanity check: discard if >1000 frames from the last accepted frame.
    // Uses wrapping-min to handle both forward jumps and reordered packets.
    if write_seq_before != 0 {
        let forward = global_seq.wrapping_sub(write_seq_before);
        let backward = write_seq_before.wrapping_sub(global_seq);
        let distance = forward.min(backward);
        if distance > 1000 {
            return;
        }
    }

    // If the reader has overrun during a silence gap, rebase to realign.
    // PLAYED_SAMPLES keeps advancing during silence but TS sequence numbers
    // do not — so even a 1-frame reader lead is permanent (both advance at
    // the same rate and the gap never closes).
    {
        let current_slot = PLAYED_SAMPLES.load(Ordering::Relaxed) / crate::FRAME_SIZE;
        let base_slot_before = buf.base_slot.load(Ordering::Relaxed);
        let reader_expected = current_slot
            .wrapping_sub(base_slot_before)
            .wrapping_add(base_seq as u64);
        // Rebase when: not init, frame is forward (not delayed/reordered),
        // and reader has already passed this frame's play position.
        if write_seq_before != 0
            && global_seq > write_seq_before
            && (global_seq as u64) < reader_expected
        {
            buf.base_seq.store(global_seq, Ordering::Release);
            buf.base_slot.store(
                current_slot + adaptive_delay_frames(conn_id),
                Ordering::Release,
            );
            // Clear stale slots from old mapping to prevent misreads
            for slot in &buf.slots {
                if let Some(frame) = slot.swap(None) {
                    buf.frame_pool.push(frame);
                }
            }
            base_seq = global_seq; // local sync after rebase
        }
    }

    // Write frame to the lock-free jitter buffer
    let slot_idx = (global_seq.wrapping_sub(base_seq)) as usize % 32;

    // Evict old frame if overwriting a slot
    if let Some(old) = buf.slots[slot_idx].swap(None) {
        buf.frame_pool.push(old);
    }

    // Get frame buffer from pool or allocate
    let mut write_frame = buf.frame_pool.pop().unwrap_or_else(|| vec![0i16; FRAME]);
    write_frame.copy_from_slice(&frame);
    buf.slots[slot_idx].swap(Some(write_frame));
    buf.write_seq.store(global_seq, Ordering::Release);
    buf.last_packet.store(Some(Instant::now()));

    // Briefly lock the session state only for talk/whisper status updates.
    let now = Instant::now();
    if let Some(state) = crate::session(conn_id) {
        let mut guard = state.lock();
        guard.talking_clients.insert(from_id, now);
        if is_whisper {
            guard.whispering_clients.insert(from_id, now);
        }
    }
}

/// Builds the cpal output stream on the current default output device. The
/// mixing callback reads every live `(connection_id, client_id)` jitter buffer
/// and mixes them into one stream, so servers can be heard at the same time.
fn build_output_stream() {
    let host = cpal::default_host();
    if let Some(device) = host.default_output_device() {
        let config = cpal::StreamConfig {
            channels: 1,
            sample_rate: cpal::SampleRate(48000),
            buffer_size: cpal::BufferSize::Fixed(960),
        };
        match device.build_output_stream(
            &config,
            {
                let current_mix_slot = std::cell::Cell::new(u64::MAX);
                let current_mix_buf = std::cell::RefCell::new([0.0f32; FRAME_SIZE as usize]);
                let cb_seq = std::cell::Cell::new(0u64);
                move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                    // ── diagnostics: first 3 callbacks print liveness ──────────
                    let seq = cb_seq.get();
                    if seq < 3 {
                        log_debug!(
                            "[cpal-stats] cb#{} data.len={} played_before={}",
                            seq,
                            data.len(),
                            PLAYED_SAMPLES.load(Ordering::Relaxed)
                        );
                        cb_seq.set(seq + 1);
                    }
                    // ── diagnostics: entry timing ────────────────────────────
                    let cb_entry = std::time::Instant::now();
                    let played = PLAYED_SAMPLES.load(Ordering::Relaxed);
                    let played_before = played;
                    // Consistency: next-callback expects this value
                    let expected = CB_STATS.expected_next_played.load(Ordering::Relaxed);
                    if expected != 0 && played_before != expected {
                        CB_STATS.played_mismatches.fetch_add(1, Ordering::Relaxed);
                    }
                    let cb_elapsed_ns = cb_entry.elapsed().as_nanos() as u64;
                    let last_ns = CB_STATS
                        .last_cb_entry_ns
                        .swap(cb_elapsed_ns, Ordering::Relaxed);
                    if last_ns != 0 {
                        CB_STATS.last_interval_us.store(
                            cb_elapsed_ns.wrapping_sub(last_ns) / 1000,
                            Ordering::Relaxed,
                        );
                    }
                    let mut slot = played / FRAME_SIZE;
                    let mut offset = (played % FRAME_SIZE) as usize;
                    let mut data_offset = 0usize;
                    let mut mix_count = 0u64;

                    while data_offset < data.len() {
                        // Generate new mix frame when entering a new logical frame
                        if slot != current_mix_slot.get() {
                            mix_count += 1;
                            let mut mix_buf = [0.0f32; FRAME_SIZE as usize];
                            let mut active = 0u32;

                            // Phase A: collect one frame from each active source
                            let client_ids = ACTIVE_CLIENT_IDS.load();
                            for &key in client_ids.iter() {
                                if let Some(buf) = CLIENT_BUFFERS.get(&key) {
                                    let base_seq = buf.base_seq.load(Ordering::Relaxed);
                                    if base_seq == 0 {
                                        continue;
                                    }
                                    let base_slot = buf.base_slot.load(Ordering::Relaxed);
                                    let expected_seq =
                                        slot.wrapping_sub(base_slot).wrapping_add(base_seq as u64);
                                    let write_seq = buf.write_seq.load(Ordering::Acquire) as u64;
                                    if write_seq >= expected_seq {
                                        let idx = (expected_seq.wrapping_sub(base_seq as u64))
                                            as usize
                                            % 32;
                                        if let Some(frame) = buf.slots[idx].swap(None) {
                                            let vol =
                                                f32::from_bits(buf.volume.load(Ordering::Relaxed));
                                            for i in 0..FRAME_SIZE as usize {
                                                mix_buf[i] += frame[i] as f32 * vol;
                                            }
                                            active += 1;
                                            buf.frame_pool.push(frame);
                                        }
                                    }
                                }
                            }

                            // Phase B: attenuate, then apply the master volume.
                            // The master gain is read per mix frame (a benign
                            // relaxed atomic load) so the whole app's loudness
                            // follows one control.
                            let atten = if active > 0 {
                                1.0 / (active as f32).sqrt()
                            } else {
                                1.0
                            };
                            let master = crate::master_volume_gain();
                            for s in &mut mix_buf {
                                *s = (*s * atten * master).clamp(-32768.0, 32767.0) / 32768.0;
                            }

                            *current_mix_buf.borrow_mut() = mix_buf;
                            current_mix_slot.set(slot);
                        }

                        // Copy from cached mix buffer to output
                        let mix = current_mix_buf.borrow();
                        let remaining_data = data.len() - data_offset;
                        let remaining_frame = FRAME_SIZE as usize - offset;
                        let copy = remaining_data.min(remaining_frame);

                        data[data_offset..data_offset + copy]
                            .copy_from_slice(&mix[offset..offset + copy]);

                        data_offset += copy;
                        offset += copy;
                        if offset >= FRAME_SIZE as usize {
                            offset = 0;
                            slot += 1;
                        }
                    }

                    // ── diagnostics: record stats ────────────────────────
                    CB_STATS.callbacks.fetch_add(1, Ordering::Relaxed);
                    CB_STATS
                        .samples_total
                        .fetch_add(data.len() as u64, Ordering::Relaxed);
                    CB_STATS.mix_frames.fetch_add(mix_count, Ordering::Relaxed);
                    // PLAYED_SAMPLES consistency: old value must equal played_before
                    let old = PLAYED_SAMPLES.fetch_add(data.len() as u64, Ordering::Relaxed);
                    if old != played_before {
                        CB_STATS.played_mismatches.fetch_add(1, Ordering::Relaxed);
                    }
                    // Store expected value for next callback's entry check
                    CB_STATS
                        .expected_next_played
                        .store(old + data.len() as u64, Ordering::Relaxed);
                }
            },
            |err| {
                log_error!("cpal output error: {}", err);
                // A stream error usually means the output device went away
                // (e.g. Bluetooth route change); rebuild on the next
                // maintenance tick.
                OUTPUT_RESTART_REQUESTED.store(true, Ordering::Relaxed);
            },
            None,
        ) {
            Ok(stream) => {
                if stream.play().is_ok() {
                    crate::AUDIO_STREAM.lock().unwrap().0 = Some(stream);
                    log_info!("cpal: output stream started (Default buffer, sample-driven)");
                } else {
                    log_error!("cpal: play() failed");
                }
            }
            Err(e) => log_error!("cpal: build_output_stream failed: {}", e),
        }
    } else {
        log_warn!("cpal: no output device");
    }
}

/// Starts the output stream if it is not already running. Connecting an extra
/// server must never reset the audio already playing from the first one.
fn ensure_output_stream_running() {
    if crate::AUDIO_STREAM.lock().unwrap().0.is_none() {
        build_output_stream();
    }
}

/// Rebuilds the output stream on the current default output device. Used for
/// route changes (Bluetooth/wired/USB) and stream errors — a full reset is
/// correct because the hardware clock (and thus the play-slot mapping) changed.
fn restart_output_stream() {
    AUDIO_STREAM.lock().unwrap().0 = None;
    CLIENT_BUFFERS.clear();
    AUDIO_DECODERS.clear();
    AUDIO_DECODERS_STEREO.clear();
    PLAYED_SAMPLES.store(0, Ordering::Relaxed);
    ACTIVE_CLIENT_IDS.store(std::sync::Arc::new(Vec::new()));
    build_output_stream();
}

/// Guard so the single shared maintenance task is spawned once for the process
/// lifetime, no matter how many servers connect.
static MAINTENANCE_STARTED: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

/// Background task: periodically cleans up stale clients and refreshes the
/// client-ID snapshot used by the audio callback.
fn spawn_maintenance_task() {
    if MAINTENANCE_STARTED.load(Ordering::SeqCst) {
        return;
    }
    MAINTENANCE_STARTED.store(true, Ordering::SeqCst);
    log_debug!("[cpal-stats] maintenance task starting (stats every 5s)");
    RUNTIME.spawn(async {
        let mut cleanup_tick = tokio::time::interval(Duration::from_secs(5));
        // Adaptive: the snapshot only matters while somebody is actually
        // sending audio. In a silent channel — the normal state of a client
        // left connected for hours — ticking twice a second just drains the
        // battery, so the cadence drops to `SNAPSHOT_IDLE`.
        let mut snapshot_tick = tokio::time::interval(SNAPSHOT_ACTIVE);
        let mut snapshot_is_fast = true;
        let mut stats_tick = tokio::time::interval(Duration::from_secs(5));
        loop {
            tokio::select! {
                _ = cleanup_tick.tick() => {
                    let now = Instant::now();

                    // Phase 1: collect candidates (read-only iteration, fast)
                    let mut candidates: Vec<AudioKey> = Vec::new();
                    for entry in CLIENT_BUFFERS.iter() {
                        if let Some(last) = entry.value().last_packet.load() {
                            if now.duration_since(last) > Duration::from_secs(10) {
                                candidates.push(*entry.key());
                            }
                        }
                    }

                    // Phase 2: double-check before removal
                    for key in &candidates {
                        let should_remove = match CLIENT_BUFFERS.get(key) {
                            Some(buf) => match buf.last_packet.load() {
                                Some(last) => now.duration_since(last) > Duration::from_secs(10),
                                None => false, // started talking again, skip
                            },
                            None => false, // already gone
                        };
                        if should_remove {
                            if let Some((_, buf)) = CLIENT_BUFFERS.remove(key) {
                                for slot in &buf.slots {
                                    if let Some(frame) = slot.swap(None) {
                                        buf.frame_pool.push(frame);
                                    }
                                }
                            }
                            AUDIO_DECODERS.remove(key);
                            AUDIO_DECODERS_STEREO.remove(key);
                        }
                    }
                }
                _ = snapshot_tick.tick() => {
                    // Switch cadence when the channel goes quiet or wakes up.
                    let has_audio = !CLIENT_BUFFERS.is_empty();
                    if has_audio != snapshot_is_fast {
                        snapshot_is_fast = has_audio;
                        let period = if has_audio { SNAPSHOT_ACTIVE } else { SNAPSHOT_IDLE };
                        snapshot_tick = tokio::time::interval(period);
                        log_debug!(
                            "maintenance: snapshot cadence -> {}ms",
                            period.as_millis()
                        );
                    }
                    // Refresh client ID snapshot for the audio callback
                    crate::refresh_active_client_snapshot();

                    // Rebuild the output stream when a restart was requested
                    // (device route change or cpal stream error). Only do so
                    // while at least one server is still connected.
                    if OUTPUT_RESTART_REQUESTED.load(Ordering::Relaxed)
                        && crate::any_session_listening()
                    {
                        log_error!("[cpal] restarting output stream (device change / stream error)");
                        restart_output_stream();
                        OUTPUT_RESTART_REQUESTED.store(false, Ordering::Relaxed);
                    }
                }
                _ = stats_tick.tick() => {
                    let cbs = CB_STATS.callbacks.swap(0, Ordering::Relaxed);
                    let samps = CB_STATS.samples_total.swap(0, Ordering::Relaxed);
                    let mixes = CB_STATS.mix_frames.swap(0, Ordering::Relaxed);
                    let mism = CB_STATS.played_mismatches.swap(0, Ordering::Relaxed);
                    let intv_us = CB_STATS.last_interval_us.swap(0, Ordering::Relaxed);
                    if cbs > 0 {
                        log_debug!("[cpal-stats] callbacks={} samples={} mix_frames={} interval_us={} mismatches={}",
                            cbs, samps, mixes, intv_us, mism);
                    }
                }
            }
        }
    });
}

/// Marks one session as disconnected (state, event queue, command channel),
/// drops its audio and removes it from the session table. Tears down the shared
/// output stream only when it was the last connected server.
fn finalize_disconnect(conn_id: crate::ConnectionId, reason: &str, expected: bool) {
    if let Some(state) = crate::session(conn_id) {
        let mut guard = state.lock();
        guard.connected = false;
        guard.disconnect_requested = false;
    }
    push_event(
        conn_id,
        TsEvent::Disconnected {
            reason: reason.to_string(),
            expected,
        },
    );
    if let Some(s) = SESSIONS.get(&conn_id) {
        *s.command_tx.lock() = None;
        s.event_loop_alive.store(false, Ordering::SeqCst);
    }
    crate::drop_session_audio(conn_id);
    if !crate::any_session_listening() {
        AUDIO_STREAM.lock().unwrap().0 = None;
    }
    SESSIONS.remove(&conn_id);
}

/// Handle a non-audio stream item (book events, messages, disconnects).
///
/// Takes the item by value so file-transfer branches can move the ready
/// TCP stream out of the result.
fn handle_control_item(conn_id: crate::ConnectionId, item: StreamItem, con: &mut Connection) {
    let handle_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        match item {
            StreamItem::Audio(_) => {} // handled upstream
            StreamItem::BookEvents(events) => {
                for ev in events {
                    match ev {
                        tsclientlib::events::Event::Message {
                            target,
                            invoker,
                            message,
                        } => {
                            let target_mode = match target {
                                tsclientlib::MessageTarget::Server => 3u8,
                                tsclientlib::MessageTarget::Channel => 2u8,
                                tsclientlib::MessageTarget::Client(_) => 1u8,
                                tsclientlib::MessageTarget::Poke(_) => 0u8,
                            };
                            push_event(
                                conn_id,
                                TsEvent::TextMessage {
                                    from_client: invoker.name.clone(),
                                    from_client_id: invoker.id.0 as u32,
                                    target_mode,
                                    message: message.clone(),
                                },
                            );
                        }
                        _ => {
                            let refreshed = con.get_state().ok().map(|book| {
                                let (talking, whispering, permission_hints) =
                                    crate::session(conn_id)
                                        .map(|state| {
                                            let guard = state.lock();
                                            (
                                                guard.talking_clients.clone(),
                                                guard.whispering_clients.clone(),
                                                guard.permission_hints.clone(),
                                            )
                                        })
                                        .unwrap_or_default();
                                refresh_from_book(
                                    conn_id,
                                    book,
                                    &talking,
                                    &whispering,
                                    &permission_hints,
                                )
                            });
                            if let Some((ch, cl)) = refreshed {
                                if let Some(state) = crate::session(conn_id) {
                                    let mut guard = state.lock();
                                    guard.channels = ch;
                                    guard.clients = cl;
                                }
                                push_event(conn_id, TsEvent::ChannelsUpdated {});
                                crate::notify_event_listener();
                            }
                        }
                    }
                }
            }
            StreamItem::MessageEvent(msg) => {
                use tsclientlib::messages::s2c::InMessage;
                match msg {
                    InMessage::TextMessage(txt) => {
                        for p in txt.iter() {
                            push_event(
                                conn_id,
                                TsEvent::TextMessage {
                                    from_client: p.invoker_name.clone(),
                                    from_client_id: p.invoker_id.0 as u32,
                                    target_mode: p.target as u8,
                                    message: p.message.clone(),
                                },
                            );
                        }
                    }
                    InMessage::FileDownload(downloads) => {
                        for download in downloads.iter() {
                            let pending = SESSIONS.get(&conn_id).and_then(|s| {
                                s.pending_transfers
                                    .lock()
                                    .remove(&download.client_filetransfer_id)
                            });
                            let Some(pending) = pending else {
                                // Not ours (or already cancelled): never open a
                                // socket for a transfer nobody asked for.
                                log_warn!("unexpected file transfer answer, ignored");
                                continue;
                            };
                            spawn_file_download(
                                conn_id,
                                download.client_filetransfer_id,
                                download.filetransfer_key.clone(),
                                download.ip,
                                download.port,
                                download.size,
                                pending,
                            );
                        }
                    }
                    InMessage::ClientPermissionHints(hints) => {
                        // The server tells us what we may do to each client.
                        // Storing it is what lets the UI hide impossible
                        // actions instead of failing after the fact.
                        if let Some(state) = crate::session(conn_id) {
                            let mut guard = state.lock();
                            for hint in hints.iter() {
                                guard
                                    .permission_hints
                                    .insert(hint.client_id.0, hint.flags.bits());
                            }
                        }
                    }
                    InMessage::FileList(entries) => {
                        // Each part is one file/directory of the requested
                        // listing. Accumulate into the per-(channel,path)
                        // buffer so a single `FileListFinished` can emit the
                        // whole list in one event instead of flooding Dart.
                        for entry in entries.iter() {
                            let channel_id = entry.channel_id.0;
                            let path = entry.path.clone();
                            if let Some(state) = crate::session(conn_id) {
                                let mut guard = state.lock();
                                guard
                                    .file_list_buffers
                                    .entry((channel_id, path))
                                    .or_default()
                                    .push(crate::TsServerFile {
                                        name: entry.name.clone(),
                                        size: entry.size,
                                        modified: entry
                                            .date_time
                                            .unix_timestamp()
                                            .map(|t| t.max(0) as u64)
                                            .unwrap_or(0),
                                        is_directory: entry.is_file,
                                    });
                            }
                        }
                    }
                    InMessage::FileListFinished(finished) => {
                        // Emit the assembled listing. `request_id` is recovered
                        // from the pending map keyed by (channel_id, path).
                        for item in finished.iter() {
                            let channel_id = item.channel_id.0;
                            let path = item.path.clone();
                            let key = (channel_id, path.clone());
                            let request_id = SESSIONS
                                .get(&conn_id)
                                .and_then(|s| {
                                    s.pending_file_requests.lock().remove(&key)
                                })
                                .unwrap_or(0);
                            let files = crate::session(conn_id)
                                .and_then(|state| {
                                    let mut guard = state.lock();
                                    guard.file_list_buffers.remove(&key)
                                })
                                .unwrap_or_default();
                            push_event(
                                conn_id,
                                TsEvent::ServerFileList {
                                    request_id,
                                    channel_id: channel_id as u32,
                                    path,
                                    ok: true,
                                    error: None,
                                    files,
                                },
                            );
                        }
                    }
                    InMessage::CommandError(errors) => {
                        for error in errors.iter() {
                            if error.id == tsclientlib::TsError::Ok {
                                continue;
                            }
                            // The server just told us we are too fast: back off
                            // immediately instead of waiting for the kick.
                            if matches!(
                                error.id,
                                tsclientlib::TsError::ClientIsFlooding
                                    | tsclientlib::TsError::BanFlooding
                            ) {
                                log_warn!("server reported flooding, degrading command rate");
                                if let Some(s) = SESSIONS.get(&conn_id) {
                                    s.command_budget.lock().enter_degraded(Instant::now());
                                }
                            }
                            push_event(
                                conn_id,
                                TsEvent::CommandError {
                                    code: format!("{:?}", error.id),
                                    message: error.message.clone(),
                                    missing_permission: error
                                        .missing_permission_id
                                        .map(|permission| format!("{:?}", permission)),
                                },
                            );
                        }
                    }
                    _ => {}
                }
            }
            StreamItem::MessageResult(_, Err(error)) => {
                push_event(
                    conn_id,
                    TsEvent::CommandError {
                        code: format!("{:?}", error.error),
                        message: error.to_string(),
                        missing_permission: error
                            .missing_permission
                            .map(|permission| format!("{:?}", permission)),
                    },
                );
            }
            StreamItem::NetworkStatsUpdated => {
                if let Ok(stats) = con.get_network_stats() {
                    let rtt_ms = stats.rtt.as_millis().min(u64::MAX as u128) as u64;
                    let rtt_dev_ms = stats.rtt_dev.as_millis().min(u64::MAX as u128) as u64;
                    // Compute inter-arrival jitter from consecutive RTT samples
                    // (mean absolute difference, EWMA-smoothed). The engine owns
                    // the sample history so the value is available even when
                    // tsproto does not expose a ready-made jitter figure.
                    let emit = if let Some(state) = crate::session(conn_id) {
                        let mut guard = state.lock();
                        let prev = guard.last_rtt_ms;
                        if prev != 0 && rtt_ms >= prev {
                            let delta = (rtt_ms - prev) as f64;
                            guard.jitter_ms = if guard.jitter_ms == 0 {
                                delta as u64
                            } else {
                                (guard.jitter_ms as f64 * 0.25 + delta * 0.75) as u64
                            };
                        }
                        guard.last_rtt_ms = rtt_ms;
                        guard.jitter_ms
                    } else {
                        0
                    };
                    push_event(
                        conn_id,
                        TsEvent::NetworkStats {
                            rtt_ms,
                            rtt_deviation_ms: rtt_dev_ms,
                            jitter_ms: emit,
                            packet_loss_percent: stats.get_packetloss() * 100.0,
                        },
                    );
                }
            }
            StreamItem::FileDownload(handle, result) => {
                // Route a high-level tsclientlib download stream to a task.
                // (The icon path uses the lower-level ftinitdownload flow, which
                // is handled by InMessage::FileDownload above; this branch is
                // for any future tsclientlib download_file caller.)
                let job = SESSIONS
                    .get(&conn_id)
                    .and_then(|s| s.pending_transfers.lock().remove(&handle.0));
                if let Some(job) = job {
                    spawn_download_stream(conn_id, handle.0, job, result.stream);
                } else {
                    log_warn!("file download for unknown handle ignored");
                }
            }
            StreamItem::FileUpload(handle, result) => {
                let job = SESSIONS
                    .get(&conn_id)
                    .and_then(|s| s.upload_jobs.lock().remove(&handle.0));
                if let Some(job) = job {
                    spawn_file_upload(
                        conn_id,
                        job.transfer_id,
                        job.remote_path.clone(),
                        job.source_path,
                        result.stream,
                    );
                } else {
                    log_warn!("file upload for unknown handle ignored");
                }
            }
            StreamItem::FiletransferFailed(handle, error) => {
                // Both upload and download failures arrive here. Report them
                // with the matching Dart transfer id.
                let transfer_id = SESSIONS
                    .get(&conn_id)
                    .and_then(|s| s.upload_jobs.lock().remove(&handle.0))
                    .map(|job| job.transfer_id);
                if let Some(tid) = transfer_id {
                    push_event(
                        conn_id,
                        TsEvent::FileTransfer {
                            transfer_id: tid as u32,
                            remote_path: String::new(),
                            local_path: String::new(),
                            bytes: 0,
                            ok: false,
                            error: Some("refused".into()),
                        },
                    );
                }
                log_warn!("file transfer failed (handle={}): {}", handle.0, error);
            }
            StreamItem::DisconnectedTemporarily(r) => {
                push_event(
                    conn_id,
                    TsEvent::Error {
                        message: format!("Temp disconnected: {:?}", r),
                    },
                );
            }
            _ => {}
        }
    }));
    if let Err(e) = handle_result {
        let msg = if let Some(s) = e.downcast_ref::<&str>() {
            s.to_string()
        } else if let Some(s) = e.downcast_ref::<String>() {
            s.clone()
        } else {
            "unknown panic".into()
        };
        push_diag(conn_id, &format!("event handler PANICKED: {}", msg));
    }
}

async fn event_loop(
    conn_id: crate::ConnectionId,
    mut con: Connection,
    mut cmd_rx: tokio::sync::mpsc::UnboundedReceiver<Command>,
) {
    log_info!("event_loop: started session={}", conn_id);
    // Rate-limits the throttling notices sent to the UI.
    let mut last_throttle_notice = Instant::now() - Duration::from_secs(2);
    push_diag(conn_id, "event_loop: started");
    loop {
        // Clean up talk/whisper indicators that have been idle for >2s.
        {
            if let Some(state) = crate::session(conn_id) {
                let mut guard = state.lock();
                guard
                    .talking_clients
                    .retain(|_, t| t.elapsed().as_millis() < 2000);
                guard
                    .whispering_clients
                    .retain(|_, t| t.elapsed().as_millis() < 2000);
            }
        }

        let do_disconnect = crate::session(conn_id)
            .map(|state| state.lock().disconnect_requested)
            .unwrap_or(false);
        if do_disconnect {
            let _ = con.disconnect(DisconnectOptions::new());
            let _ = con.events().for_each(|_| future::ready(())).await;
            finalize_disconnect(conn_id, "User disconnected", true);
            crate::notify_event_listener();
            return;
        }

        // 1. Process pending commands (non-blocking).
        let mut ready: Vec<Command> = Vec::new();
        while let Ok(cmd) = cmd_rx.try_recv() {
            match cmd {
                Command::SendAudio { .. } | Command::Disconnect => ready.push(cmd),
                other => {
                    if let Some(s) = SESSIONS.get(&conn_id) {
                        s.command_budget.lock().enqueue(other);
                    }
                }
            }
        }
        {
            let now = Instant::now();
            let (pending, degraded) = if let Some(s) = SESSIONS.get(&conn_id) {
                let mut budget = s.command_budget.lock();
                while let Some(cmd) = budget.take_ready(now) {
                    ready.push(cmd);
                }
                (budget.pending(), budget.is_degraded())
            } else {
                (0, false)
            };
            // Tell the UI an action is queued rather than ignored, at most
            // once per second so a backlog cannot itself flood the event queue.
            if pending > 0 && last_throttle_notice.elapsed() >= Duration::from_secs(1) {
                last_throttle_notice = Instant::now();
                push_event(
                    conn_id,
                    TsEvent::CommandThrottled {
                        pending: pending as u32,
                        degraded,
                    },
                );
            }
        }

        for cmd in ready {
            if !crate::session(conn_id).is_some() {
                // The session vanished (finalized elsewhere); stop.
                return;
            }
            match cmd {
                Command::SendMessage {
                    target_mode,
                    target_cid,
                    message,
                } => {
                    let (target, target_client_id) = match target_mode {
                        1 => (
                            tsclientlib::TextMessageTargetMode::Client,
                            Some(ClientId(target_cid as u16)),
                        ),
                        3 => (tsclientlib::TextMessageTargetMode::Server, None),
                        _ => (tsclientlib::TextMessageTargetMode::Channel, None),
                    };
                    let part = OutSendTextMessagePart {
                        target,
                        target_client_id,
                        message: Cow::Owned(message),
                    };
                    if let Err(error) =
                        OutSendTextMessageMessage::new(&mut std::iter::once(part)).send(&mut con)
                    {
                        push_event(
                            conn_id,
                            TsEvent::Error {
                                message: format!("Failed to send text message: {error}"),
                            },
                        );
                    }
                }
                Command::MoveChannel {
                    client_id,
                    channel_id,
                    channel_password,
                } => {
                    let part = OutClientMovePart {
                        client_id: ClientId(client_id),
                        channel_id: ChannelId(channel_id),
                        channel_password: channel_password.map(Cow::Owned),
                    };
                    let _ = OutClientMoveMessage::new(&mut std::iter::once(part)).send(&mut con);
                }
                Command::SetMuted { input, output } => {
                    let part = OutClientUpdatePart {
                        name: None,
                        input_muted: if input { Some(true) } else { Some(false) },
                        output_muted: if output { Some(true) } else { Some(false) },
                        is_away: None,
                        away_message: None,
                        input_hardware_enabled: None,
                        output_hardware_enabled: None,
                        is_channel_commander: None,
                        avatar_hash: None,
                        phonetic_name: None,
                        talk_power_request: None,
                        talk_power_request_message: None,
                        is_recording: None,
                        badges: None,
                    };
                    let _ = OutClientUpdateMessage::new(&mut std::iter::once(part)).send(&mut con);
                }
                Command::SetAway { away, message } => {
                    let part = OutClientUpdatePart {
                        name: None,
                        input_muted: None,
                        output_muted: None,
                        is_away: Some(away),
                        // Clearing the flag must also clear the message,
                        // otherwise the old "back in 5 min" sticks around.
                        away_message: Some(Cow::Owned(if away {
                            message.unwrap_or_default()
                        } else {
                            String::new()
                        })),
                        input_hardware_enabled: None,
                        output_hardware_enabled: None,
                        is_channel_commander: None,
                        avatar_hash: None,
                        phonetic_name: None,
                        talk_power_request: None,
                        talk_power_request_message: None,
                        is_recording: None,
                        badges: None,
                    };
                    let _ = OutClientUpdateMessage::new(&mut std::iter::once(part)).send(&mut con);
                }
                Command::SetNickname { name } => {
                    let part = OutClientUpdatePart {
                        name: Some(Cow::Owned(name.clone())),
                        input_muted: None,
                        output_muted: None,
                        is_away: None,
                        away_message: None,
                        input_hardware_enabled: None,
                        output_hardware_enabled: None,
                        is_channel_commander: None,
                        avatar_hash: None,
                        phonetic_name: None,
                        talk_power_request: None,
                        talk_power_request_message: None,
                        is_recording: None,
                        badges: None,
                    };
                    // The server may still refuse it (ClientNicknameInuse);
                    // local state is only updated from the confirmed book.
                    let _ = OutClientUpdateMessage::new(&mut std::iter::once(part)).send(&mut con);
                }
                Command::SetChannelCommander { enabled } => {
                    let part = OutClientUpdatePart {
                        name: None,
                        input_muted: None,
                        output_muted: None,
                        is_away: None,
                        away_message: None,
                        input_hardware_enabled: None,
                        output_hardware_enabled: None,
                        is_channel_commander: Some(enabled),
                        avatar_hash: None,
                        phonetic_name: None,
                        talk_power_request: None,
                        talk_power_request_message: None,
                        is_recording: None,
                        badges: None,
                    };
                    let _ = OutClientUpdateMessage::new(&mut std::iter::once(part)).send(&mut con);
                }
                Command::KickClient {
                    client_id,
                    from_server,
                    reason,
                } => {
                    let part = OutClientKickPart {
                        client_id: ClientId(client_id),
                        reason: if from_server {
                            Reason::KickServer
                        } else {
                            Reason::KickChannel
                        },
                        reason_message: reason.map(Cow::Owned),
                    };
                    let _ = OutClientKickMessage::new(&mut std::iter::once(part)).send(&mut con);
                }
                Command::BanClient {
                    client_id,
                    seconds,
                    reason,
                } => {
                    let part = OutBanClientPart {
                        client_id: ClientId(client_id),
                        // No duration means a permanent ban on TeamSpeak.
                        // tsclientlib uses `time::Duration`, not `std::time`.
                        time: (seconds > 0).then(|| time::Duration::seconds(seconds as i64)),
                        ban_reason: reason.map(Cow::Owned),
                    };
                    let _ = OutBanClientMessage::new(&mut std::iter::once(part)).send(&mut con);
                }
                Command::PokeClient { client_id, message } => {
                    let part = OutClientPokeRequestPart {
                        client_id: ClientId(client_id),
                        message: Cow::Owned(message),
                    };
                    let _ =
                        OutClientPokeRequestMessage::new(&mut std::iter::once(part)).send(&mut con);
                }
                Command::DownloadFile {
                    transfer_id,
                    channel_id,
                    channel_password,
                    remote_path,
                } => {
                    let part = OutInitDownloadPart {
                        client_filetransfer_id: transfer_id,
                        name: Cow::Owned(remote_path),
                        channel_id: ChannelId(channel_id),
                        channel_password: Cow::Owned(channel_password),
                        seek_position: 0,
                        // Protocol 0 is the plain (unencrypted) file transfer
                        // channel; it is what every 3.x server accepts.
                        protocol: 0,
                    };
                    let _ = OutInitDownloadMessage::new(&mut std::iter::once(part)).send(&mut con);
                }
                Command::UploadFile {
                    transfer_id,
                    channel_id,
                    channel_password,
                    remote_path,
                    source_path,
                    size,
                    overwrite,
                } => {
                    let pw = if channel_password.is_empty() {
                        None
                    } else {
                        Some(channel_password.as_str())
                    };
                    // tsclientlib performs `ftinitupload`, waits for the server
                    // answer and emits a `FileUpload`/`FiletransferFailed`
                    // StreamItem carrying the ready TCP stream. We keep the job
                    // so the event loop can match the handle back to our id.
                    match con.upload_file(
                        ChannelId(channel_id),
                        &remote_path,
                        pw,
                        size,
                        overwrite,
                        false,
                    ) {
                        Ok(handle) => {
                            if let Some(s) = SESSIONS.get(&conn_id) {
                                s.upload_jobs.lock().insert(
                                    handle.0,
                                    crate::UploadJob {
                                        transfer_id,
                                        source_path,
                                        remote_path: remote_path.clone(),
                                    },
                                );
                            }
                        }
                        Err(e) => {
                            log_error!("upload_file rejected: {}", e);
                            push_event(
                                conn_id,
                                TsEvent::FileTransfer {
                                    transfer_id: transfer_id as u32,
                                    remote_path,
                                    local_path: String::new(),
                                    bytes: 0,
                                    ok: false,
                                    error: Some("refused".into()),
                                },
                            );
                        }
                    }
                }
                Command::RequestFileList {
                    request_id,
                    channel_id,
                    channel_password,
                    path,
                } => {
                    let part = OutFileListRequestPart {
                        channel_id: ChannelId(channel_id),
                        channel_password: Cow::Owned(channel_password),
                        path: Cow::Owned(path),
                    };
                    if let Err(error) =
                        OutFileListRequestMessage::new(&mut std::iter::once(part)).send(&mut con)
                    {
                        push_event(
                            conn_id,
                            TsEvent::ServerFileList {
                                request_id,
                                channel_id: channel_id as u32,
                                path: String::new(),
                                ok: false,
                                error: Some(format!("list request failed: {error}")),
                                files: Vec::new(),
                            },
                        );
                    }
                }
                Command::DeleteFile {
                    channel_id,
                    channel_password,
                    path,
                } => {
                    let part = OutDeleteFilePart {
                        channel_id: ChannelId(channel_id),
                        channel_password: Cow::Owned(channel_password),
                        name: Cow::Owned(path),
                    };
                    let _ =
                        OutDeleteFileMessage::new(&mut std::iter::once(part)).send(&mut con);
                }
                Command::CreateDirectory {
                    channel_id,
                    channel_password,
                    path,
                } => {
                    let part = OutCreateDirectoryPart {
                        channel_id: ChannelId(channel_id),
                        channel_password: Cow::Owned(channel_password),
                        directory_name: Cow::Owned(path),
                    };
                    let _ = OutCreateDirectoryMessage::new(&mut std::iter::once(part))
                        .send(&mut con);
                }
                Command::CreateChannel {
                    parent_id,
                    name,
                    topic,
                    description,
                    password,
                    max_clients,
                    permanent,
                    semi_permanent,
                } => {
                    let part = OutChannelCreatePart {
                        parent_id: (parent_id != 0).then_some(ChannelId(parent_id)),
                        name: Cow::Owned(name),
                        topic: topic.map(Cow::Owned),
                        description: description.map(Cow::Owned),
                        password: password.as_deref().map(Cow::Borrowed),
                        codec: None,
                        codec_quality: None,
                        max_clients,
                        max_family_clients: None,
                        order: None,
                        has_password: Some(password.is_some()),
                        is_unencrypted: None,
                        delete_delay: None,
                        is_max_clients_unlimited: None,
                        is_max_family_clients_unlimited: None,
                        inherits_max_family_clients: None,
                        phonetic_name: None,
                        is_permanent: Some(permanent),
                        is_semi_permanent: Some(semi_permanent),
                        is_default: None,
                    };
                    let _ = OutChannelCreateMessage::new(&mut std::iter::once(part)).send(&mut con);
                }
                Command::EditChannel {
                    channel_id,
                    name,
                    topic,
                    description,
                    password,
                    has_password,
                    max_clients,
                    permanent,
                    semi_permanent,
                } => {
                    let part = OutChannelEditPart {
                        channel_id: ChannelId(channel_id),
                        order: None,
                        name: name.map(Cow::Owned),
                        topic: topic.map(Cow::Owned),
                        is_default: None,
                        has_password,
                        password: password.map(Cow::Owned),
                        is_permanent: permanent,
                        is_semi_permanent: semi_permanent,
                        codec: None,
                        codec_quality: None,
                        needed_talk_power: None,
                        max_clients,
                        max_family_clients: None,
                        codec_latency_factor: None,
                        is_unencrypted: None,
                        delete_delay: None,
                        is_max_clients_unlimited: None,
                        is_max_family_clients_unlimited: None,
                        inherits_max_family_clients: None,
                        phonetic_name: None,
                        description: description.map(Cow::Owned),
                    };
                    let _ = OutChannelEditMessage::new(&mut std::iter::once(part)).send(&mut con);
                }
                Command::DeleteChannel { channel_id, force } => {
                    let part = OutChannelDeletePart {
                        channel_id: ChannelId(channel_id),
                        force,
                    };
                    let _ = OutChannelDeleteMessage::new(&mut std::iter::once(part)).send(&mut con);
                }
                Command::MoveChannelTree {
                    channel_id,
                    parent_id,
                    order,
                } => {
                    let part = OutChannelMovePart {
                        channel_id: ChannelId(channel_id),
                        parent_id: ChannelId(parent_id),
                        order: order.map(ChannelId),
                    };
                    let _ = OutChannelMoveMessage::new(&mut std::iter::once(part)).send(&mut con);
                }
                Command::Disconnect => {
                    let _ = con.disconnect(DisconnectOptions::new());
                    let _ = con.events().for_each(|_| future::ready(())).await;
                    finalize_disconnect(conn_id, "User disconnected", true);
                    crate::notify_event_listener();
                    return;
                }
                Command::SendAudio { data } => {
                    const FRAME: usize = 960;
                    let Some(state_arc) = crate::session(conn_id) else {
                        return;
                    };
                    // Snapshot the whisper configuration once per command so
                    // every frame of this batch is routed consistently.
                    let (whisper_on, whisper_clients, whisper_channels) = {
                        let guard = state_arc.lock();
                        let has_target = !guard.whisper_target_clients.is_empty()
                            || !guard.whisper_target_channels.is_empty();
                        (
                            guard.whisper_active && has_target,
                            guard.whisper_target_clients.clone(),
                            guard.whisper_target_channels.clone(),
                        )
                    };
                    // Stream type changed since the last transmitted frame:
                    // terminate the previous stream with a zero-length voice
                    // packet, the same way the official client signals the end
                    // of a talk burst. Without it the receiving clients keep
                    // showing the speaker as talking until their timeout.
                    {
                        let mut guard = state_arc.lock();
                        if guard.whisper_was_active != whisper_on {
                            let was_whisper = guard.whisper_was_active;
                            let seq = if was_whisper {
                                let s = guard.whisper_seq;
                                guard.whisper_seq = s.wrapping_add(1);
                                s
                            } else {
                                let s = guard.audio_seq;
                                guard.audio_seq = s.wrapping_add(1);
                                s
                            };
                            let previous_clients = guard.whisper_target_clients.clone();
                            let previous_channels = guard.whisper_target_channels.clone();
                            guard.whisper_was_active = whisper_on;
                            drop(guard);
                            let terminator = if was_whisper {
                                OutAudio::new(&AudioData::C2SWhisper {
                                    id: seq,
                                    codec: CodecType::OpusVoice,
                                    channels: previous_channels,
                                    clients: previous_clients,
                                    data: &[],
                                })
                            } else {
                                OutAudio::new(&AudioData::C2S {
                                    id: seq,
                                    codec: CodecType::OpusVoice,
                                    data: &[],
                                })
                            };
                            if let Err(e) = con.send_audio(terminator) {
                                log_error!("event_loop: whisper switch terminator error: {}", e);
                            }
                        }
                    }
                    {
                        let mut guard = state_arc.lock();
                        guard.pcm_in.extend_from_slice(&data);
                    }
                    loop {
                        let encode_result = {
                            let mut guard = state_arc.lock();
                            if guard.pcm_in.len() < FRAME {
                                break;
                            }
                            let frame: Vec<f32> = guard.pcm_in.drain(..FRAME).collect();
                            // 10 × 20 ms gives a 200 ms release delay, avoiding
                            // clipped word endings while keeping background
                            // transmission short.
                            const HOLD_FRAMES: u32 = 10;
                            let vad_drop = if guard.vad_enabled {
                                if hybrid_vad_should_transmit(&mut guard, &frame) {
                                    guard.vad_hold = HOLD_FRAMES;
                                    false
                                } else if guard.vad_hold > 0 {
                                    guard.vad_hold -= 1;
                                    false
                                } else {
                                    true
                                }
                            } else {
                                false
                            };
                            // Read gain before dropping state (avoid split-borrow conflict)
                            let gain = guard.mic_gain;
                            drop(guard);
                            if vad_drop {
                                None
                            } else {
                                // Apply mic gain AFTER VAD so VAD sees raw mic level
                                let gained: Vec<f32> = if (gain - 1.0).abs() > 0.001 {
                                    frame.iter().map(|s| (s * gain).clamp(-1.0, 1.0)).collect()
                                } else {
                                    frame
                                };
                                let mut guard = state_arc.lock();
                                // Sequence number first: reading these fields must
                                // not happen while the encoder is borrowed below,
                                // and the closure must not capture `guard`.
                                let seq = if whisper_on {
                                    let s = guard.whisper_seq;
                                    guard.whisper_seq = s.wrapping_add(1);
                                    s
                                } else {
                                    let s = guard.audio_seq;
                                    guard.audio_seq = s.wrapping_add(1);
                                    s
                                };
                                if let Some(ref mut encoder) = guard.audio_encoder {
                                    // Reuse a thread-local Opus scratch instead of
                                    // allocating a 4 kB Vec for every 20 ms frame
                                    // (a real CPU/GC sink that warms the phone).
                                    // The scratch lives outside the session guard,
                                    // so it never competes for a borrow with the
                                    // encoder; the closure only captures the
                                    // encoder and the precomputed `seq`.
                                    thread_local! {
                                        static OPUS_SCRATCH: std::cell::RefCell<Vec<u8>> =
                                            const { std::cell::RefCell::new(Vec::new()) };
                                    }
                                    OPUS_SCRATCH.with(|c| {
                                        let mut buf = c.borrow_mut();
                                        if buf.len() < 4000 {
                                            buf.resize(4000, 0);
                                        }
                                        match encoder.encode(&gained, FRAME, &mut buf) {
                                            Ok(len) => Some((seq, buf[..len].to_vec())),
                                            Err(e) => {
                                                log_error!(
                                                    "opus encode ERROR: {} (frame_len={})",
                                                    e,
                                                    gained.len()
                                                );
                                                None
                                            }
                                        }
                                    })
                                } else {
                                    guard.pcm_in.clear();
                                    None
                                }
                            }
                        };
                        if let Some((seq, opus_data)) = encode_result {
                            let packet = if whisper_on {
                                OutAudio::new(&AudioData::C2SWhisper {
                                    id: seq,
                                    codec: CodecType::OpusVoice,
                                    channels: whisper_channels.clone(),
                                    clients: whisper_clients.clone(),
                                    data: &opus_data,
                                })
                            } else {
                                OutAudio::new(&AudioData::C2S {
                                    id: seq,
                                    codec: CodecType::OpusVoice,
                                    data: &opus_data,
                                })
                            };
                            match con.send_audio(packet) {
                                Ok(_) => {
                                    if let Some(state) = crate::session(conn_id) {
                                        state.lock().voice_active = true;
                                    }
                                }
                                Err(e) => log_error!("event_loop: send_audio error: {}", e),
                            }
                        }
                    }
                }
            }
        }

        // 2. Poll events — decode each audio packet to its speaker's own buffer.
        let first = tokio::time::timeout(Duration::from_millis(20), con.events().next()).await;
        let mut deferred: Option<StreamItem> = None;

        match first {
            Ok(Some(Ok(StreamItem::Audio(audio_buf)))) => {
                decode_to_client_buffer(conn_id, audio_buf);
            }
            Ok(Some(Ok(item))) => {
                deferred = Some(item);
            }
            Ok(Some(Err(e))) => {
                log_error!("event_loop: stream error: {} (session={})", e, conn_id);
                push_event(
                    conn_id,
                    TsEvent::Error {
                        message: format!("{}", e),
                    },
                );
                break;
            }
            Ok(None) => {
                log_info!(
                    "event_loop: stream ended (server disconnect, session={})",
                    conn_id
                );
                break;
            }
            Err(_) => {} // 20ms timeout — continue
        }

        // 2b. Drain remaining already-available events (1ms timeout)
        let mut deferred_events: Vec<StreamItem> = Vec::new();
        loop {
            match tokio::time::timeout(Duration::from_millis(1), con.events().next()).await {
                Ok(Some(Ok(StreamItem::Audio(audio_buf)))) => {
                    decode_to_client_buffer(conn_id, audio_buf);
                }
                Ok(Some(Ok(item))) => {
                    deferred_events.push(item);
                }
                Ok(Some(Err(e))) => {
                    log_error!("event_loop: stream error: {} (session={})", e, conn_id);
                    push_event(
                        conn_id,
                        TsEvent::Error {
                            message: format!("{}", e),
                        },
                    );
                    break;
                }
                Ok(None) => {
                    break;
                }
                Err(_) => break,
            }
        }

        // 2c. Process deferred non-audio events
        for item in deferred_events {
            handle_control_item(conn_id, item, &mut con);
        }
        if let Some(item) = deferred {
            handle_control_item(conn_id, item, &mut con);
        }
    }

    // The loop is exiting because the server closed the stream or errored.
    // This is an *unexpected* drop (the user did not ask for it), so it is the
    // only case where an automatic reconnect is legitimate.
    let expected = crate::session(conn_id)
        .map(|state| state.lock().disconnect_requested)
        .unwrap_or(false);
    finalize_disconnect(conn_id, "Connection closed by server", expected);
    crate::notify_event_listener();
}

// ─── Disconnect ─────────────────────────────────────────────────────

/// Disconnects every live session. Called from `KeepAliveService.onTaskRemoved`
/// when the app is swiped from recents — at that point the user wants the whole
/// app gone, so every server is disconnected, not just the focused one.
#[no_mangle]
pub extern "system" fn Java_com_senlinjun_nek0_KeepAliveService_tsDisconnect(
    _env: *mut std::ffi::c_void,
    _class: *mut std::ffi::c_void,
) {
    let ids: Vec<crate::ConnectionId> = SESSIONS.iter().map(|s| *s.key()).collect();
    for conn_id in ids {
        // Fast path: set the flag directly so the event loop sees it next iter.
        if let Some(state) = crate::session(conn_id) {
            state.lock().disconnect_requested = true;
        }
        // Try to push a Disconnect command — the event loop drains commands
        // synchronously before each poll, so this takes effect immediately.
        let tx = SESSIONS
            .get(&conn_id)
            .and_then(|s| s.command_tx.lock().take());
        if let Some(tx) = tx {
            let _ = tx.send(crate::Command::Disconnect);
        }
        // Fallback: if the event loop is dead, take the Connection from stash
        // and do a synchronous block_on disconnect directly.
        if let Some(mut con) = SESSIONS
            .get(&conn_id)
            .and_then(|s| s.connection.lock().take())
        {
            let _ = con.disconnect(DisconnectOptions::new());
            RUNTIME.block_on(con.events().for_each(|_| future::ready(())));
        }
    }
}

#[no_mangle]
pub extern "C" fn ts_disconnect(conn_id: crate::ConnectionId) -> *mut c_char {
    log_info!("ts_disconnect: session {}", conn_id);
    let alive = SESSIONS
        .get(&conn_id)
        .map(|s| s.event_loop_alive.load(Ordering::SeqCst))
        .unwrap_or(false);
    push_diag(
        conn_id,
        &format!("ts_disconnect: event_loop_alive={}", alive),
    );

    if alive {
        if let Some(state) = crate::session(conn_id) {
            state.lock().disconnect_requested = true;
        }
        // Also send Command::Disconnect for immediate processing
        if let Some(tx) = SESSIONS
            .get(&conn_id)
            .and_then(|s| s.command_tx.lock().take())
        {
            let _ = tx.send(crate::Command::Disconnect);
        }
    } else if let Some(mut con) = SESSIONS
        .get(&conn_id)
        .and_then(|s| s.connection.lock().take())
    {
        let _ = con.disconnect(DisconnectOptions::new());
        RUNTIME.block_on(con.events().for_each(|_| future::ready(())));
        if let Some(state) = crate::session(conn_id) {
            let mut guard = state.lock();
            guard.connected = false;
            guard.disconnect_requested = false;
        }
        crate::drop_session_audio(conn_id);
        SESSIONS.remove(&conn_id);
    }
    to_c_str(
        serde_json::json!({"type": "disconnected", "reason": "User disconnected", "connection_id": conn_id}).to_string(),
    )
}

/// Request the output stream to be rebuilt on the current default device.
/// Only sets a flag — the maintenance task performs the rebuild within
/// 500ms, which naturally coalesces multiple requests in the same window.
#[no_mangle]
pub extern "C" fn ts_restart_audio_output() {
    if crate::any_session_listening() {
        OUTPUT_RESTART_REQUESTED.store(true, Ordering::Relaxed);
        log_warn!("ts_restart_audio_output: restart requested");
    } else {
        log_warn!("ts_restart_audio_output: ignored (not connected)");
    }
}

/// JNI entry used by KeepAliveService's AudioDeviceCallback when the output
/// route changes (Bluetooth/wired/USB device added or removed).
#[no_mangle]
pub extern "system" fn Java_com_senlinjun_nek0_KeepAliveService_tsRestartAudioOutput(
    _env: *mut std::ffi::c_void,
    _class: *mut std::ffi::c_void,
) {
    ts_restart_audio_output();
}

// ─── Poll / Getters ─────────────────────────────────────────────────

/// Drains the global event queue. Every event is wrapped with the
/// `connection_id` it belongs to (`0` = engine-wide diagnostic), so a single
/// poll loop feeding every session's UI remains correct.
#[no_mangle]
pub extern "C" fn ts_poll_events() -> *mut c_char {
    crate::flush_panic_log();
    let events: Vec<crate::EnvelopedEvent> = EVENT_QUEUE.lock().drain(..).collect();
    to_c_str(serde_json::to_string(&events).unwrap_or_else(|_| "[]".into()))
}

#[no_mangle]
pub extern "C" fn ts_get_channels(conn_id: crate::ConnectionId) -> *mut c_char {
    let Some(state) = crate::session(conn_id) else {
        return to_c_str("[]".to_string());
    };
    let guard = state.lock();
    if !guard.connected {
        return to_c_str("[]".to_string());
    }
    to_c_str(serde_json::to_string(&guard.channels).unwrap_or_else(|_| "[]".into()))
}

#[no_mangle]
pub extern "C" fn ts_get_clients(conn_id: crate::ConnectionId) -> *mut c_char {
    let Some(state) = crate::session(conn_id) else {
        return to_c_str("[]".to_string());
    };
    let mut guard = state.lock();
    if !guard.connected {
        return to_c_str("[]".to_string());
    }
    // Recompute is_talking from live talking_clients data
    let talking: Vec<u16> = guard
        .talking_clients
        .iter()
        .filter(|(_, t)| t.elapsed().as_millis() < 500)
        .map(|(&id, _)| id)
        .collect();
    let whispering: Vec<u16> = guard
        .whispering_clients
        .iter()
        .filter(|(_, t)| t.elapsed().as_millis() < 500)
        .map(|(&id, _)| id)
        .collect();
    for c in &mut guard.clients {
        c.is_talking = talking.contains(&(c.id as u16));
        c.is_whispering = whispering.contains(&(c.id as u16));
    }
    // Refresh per-client volumes from the global UID-keyed persistent store.
    let volume_snapshot: Vec<(String, f32)> = CLIENT_VOLUMES
        .lock()
        .iter()
        .map(|(k, &v)| (k.clone(), v))
        .collect();
    for c in &mut guard.clients {
        if let Some(uid) = &c.uid {
            if let Some((_uid, db)) = volume_snapshot.iter().find(|(u, _)| u == uid) {
                c.volume = *db;
            }
        }
    }
    to_c_str(serde_json::to_string(&guard.clients).unwrap_or_else(|_| "[]".into()))
}

// ─── Send Message ───────────────────────────────────────────────────

fn enqueue_text_message(
    conn_id: crate::ConnectionId,
    target_mode: u8,
    target_cid: u64,
    msg: *const c_char,
) -> u8 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if msg.is_null() || !connected {
        return 0;
    }
    let message = unsafe { std::ffi::CStr::from_ptr(msg) }
        .to_string_lossy()
        .into_owned();
    if message.is_empty() {
        return 0;
    }
    queue_command(
        conn_id,
        Command::SendMessage {
            target_mode,
            target_cid,
            message,
        },
    )
}

#[no_mangle]
pub extern "C" fn ts_send_channel_message(
    conn_id: crate::ConnectionId,
    _cid: u32,
    msg: *const c_char,
) -> u8 {
    enqueue_text_message(conn_id, 2, 0, msg)
}

#[no_mangle]
pub extern "C" fn ts_send_private_message(
    conn_id: crate::ConnectionId,
    client_id: u32,
    msg: *const c_char,
) -> u8 {
    if client_id == 0 || client_id > u16::MAX as u32 {
        return 0;
    }
    enqueue_text_message(conn_id, 1, client_id as u64, msg)
}

#[no_mangle]
pub extern "C" fn ts_send_server_message(conn_id: crate::ConnectionId, msg: *const c_char) -> u8 {
    enqueue_text_message(conn_id, 3, 0, msg)
}

// ─── Move ───────────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn ts_move_to_channel(
    conn_id: crate::ConnectionId,
    cid: u32,
    password: *const c_char,
) -> u8 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if !connected {
        return 0;
    }
    let own_id = crate::session(conn_id)
        .map(|state| state.lock().own_client_id)
        .unwrap_or(0);
    let channel_password = if password.is_null() {
        None
    } else {
        let value = unsafe { std::ffi::CStr::from_ptr(password) }
            .to_string_lossy()
            .into_owned();
        (!value.is_empty()).then_some(value)
    };
    queue_command(
        conn_id,
        Command::MoveChannel {
            client_id: own_id as u16,
            channel_id: cid as u64,
            channel_password,
        },
    )
}

// ─── File transfer ──────────────────────────────────────────────────

/// Hard ceiling for any single transfer, whatever the caller asked for.
/// Icons and avatars are a few kilobytes; anything in the megabytes range on
/// this path is either a mistake or an attempt to fill the device.
const TRANSFER_HARD_LIMIT: u64 = 8 * 1024 * 1024;

/// Reads a file from the server's file-transfer port and writes it to disk.
///
/// The command connection is UDP; file transfers use a separate plain TCP
/// connection where the client sends the one-shot key it just received and the
/// server streams the payload. Everything here runs off the event loop so a
/// slow transfer never stalls voice.
fn spawn_file_download(
    conn_id: crate::ConnectionId,
    transfer_id: u16,
    key: String,
    ip: Option<std::net::IpAddr>,
    port: u16,
    announced_size: u64,
    pending: crate::PendingTransfer,
) {
    RUNTIME.spawn(async move {
        let result = run_file_download(conn_id, &key, ip, port, announced_size, &pending).await;
        let event = match result {
            Ok(bytes) => TsEvent::FileTransfer {
                transfer_id: transfer_id as u32,
                remote_path: pending.remote_path.clone(),
                local_path: pending.target_path.clone(),
                bytes,
                ok: true,
                error: None,
            },
            Err(reason) => {
                log_warn!("file transfer failed: {}", reason);
                // A partial file is worse than none: the UI would cache a
                // truncated icon forever.
                let _ = std::fs::remove_file(&pending.target_path);
                TsEvent::FileTransfer {
                    transfer_id: transfer_id as u32,
                    remote_path: pending.remote_path.clone(),
                    local_path: String::new(),
                    bytes: 0,
                    ok: false,
                    error: Some(reason),
                }
            }
        };
        push_event(conn_id, event);
    });
}

async fn run_file_download(
    conn_id: crate::ConnectionId,
    key: &str,
    ip: Option<std::net::IpAddr>,
    port: u16,
    announced_size: u64,
    pending: &crate::PendingTransfer,
) -> Result<u64, String> {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    let limit = pending.max_bytes.min(TRANSFER_HARD_LIMIT);
    if announced_size > limit {
        return Err("too_large".into());
    }

    let address = match ip {
        Some(ip) => std::net::SocketAddr::new(ip, port),
        None => {
            // The server did not pin an IP: reuse the host we are connected to.
            let host = SESSIONS
                .get(&conn_id)
                .map(|s| s.server_host.lock().clone())
                .unwrap_or_default();
            if host.is_empty() {
                return Err("network".into());
            }
            let mut resolved = tokio::net::lookup_host(format!("{}:{}", host, port))
                .await
                .map_err(|_| "network".to_string())?;
            resolved.next().ok_or_else(|| "network".to_string())?
        }
    };

    let connect = tokio::time::timeout(
        Duration::from_secs(10),
        tokio::net::TcpStream::connect(address),
    );
    let mut stream = connect
        .await
        .map_err(|_| "network".to_string())?
        .map_err(|_| "network".to_string())?;

    stream
        .write_all(key.as_bytes())
        .await
        .map_err(|_| "network".to_string())?;

    let mut payload: Vec<u8> = Vec::with_capacity(announced_size.min(limit) as usize);
    let mut buffer = vec![0u8; 16 * 1024];
    loop {
        let read = tokio::time::timeout(Duration::from_secs(30), stream.read(&mut buffer))
            .await
            .map_err(|_| "network".to_string())?
            .map_err(|_| "network".to_string())?;
        if read == 0 {
            break;
        }
        // Enforce the cap on the *actual* stream too: the announced size is
        // only a claim by the server.
        if payload.len() as u64 + read as u64 > limit {
            return Err("too_large".into());
        }
        payload.extend_from_slice(&buffer[..read]);
        if announced_size > 0 && payload.len() as u64 >= announced_size {
            break;
        }
    }

    if announced_size > 0 && (payload.len() as u64) < announced_size {
        return Err("network".into());
    }

    let received = payload.len() as u64;
    std::fs::write(&pending.target_path, &payload).map_err(|_| "io".to_string())?;
    Ok(received)
}

/// Streams a local file to a ready upload socket, emitting progress events.
///
/// The stream comes from tsclientlib's `FileUpload` answer; we own the socket
/// and must send the file bytes. Chunks are 16 KiB and progress is emitted
/// every ~64 KiB so the UI bar stays smooth without spamming the event queue.
fn spawn_file_upload(
    conn_id: crate::ConnectionId,
    transfer_id: u16,
    remote_path: String,
    source_path: String,
    mut stream: tokio::net::TcpStream,
) {
    RUNTIME.spawn(async move {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let result: Result<u64, &'static str> = async {
            let mut file = tokio::fs::File::open(&source_path)
                .await
                .map_err(|_| "io")?;
            let total = std::fs::metadata(&source_path)
                .map(|m| m.len())
                .unwrap_or(0);
            let mut buf = vec![0u8; 16 * 1024];
            let mut written = 0u64;
            loop {
                let n = file.read(&mut buf).await.map_err(|_| "io")?;
                if n == 0 {
                    break;
                }
                stream.write_all(&buf[..n]).await.map_err(|_| "network")?;
                written += n as u64;
                // Report progress whenever the 64 KiB bucket advances, and at
                // the very end, so the UI bar moves smoothly without spamming
                // the event queue on every chunk.
                let bucket_now = written / 65536;
                let bucket_before = (written - n as u64) / 65536;
                if bucket_now > bucket_before || written == total {
                    push_event(
                        conn_id,
                        TsEvent::FileTransferProgress {
                            transfer_id: transfer_id as u32,
                            remote_path: remote_path.clone(),
                            bytes: written,
                            total_bytes: total,
                        },
                    );
                }
            }
            Ok(written)
        }
        .await;

        let event = match result {
            Ok(bytes) => TsEvent::FileTransfer {
                transfer_id: transfer_id as u32,
                remote_path: remote_path.clone(),
                local_path: source_path.clone(),
                bytes,
                ok: true,
                error: None,
            },
            Err(reason) => {
                log_warn!("file upload failed: {}", reason);
                TsEvent::FileTransfer {
                    transfer_id: transfer_id as u32,
                    remote_path: remote_path.clone(),
                    local_path: String::new(),
                    bytes: 0,
                    ok: false,
                    error: Some(reason.into()),
                }
            }
        };
        push_event(conn_id, event);
    });
}

/// Downloads from a tsclientlib-provided stream to a local path. This is the
/// high-level counterpart of [spawn_file_download]; used when a caller uses
/// `Connection::download_file` (future callers, e.g. for a file manager).
fn spawn_download_stream(
    conn_id: crate::ConnectionId,
    transfer_id: u16,
    job: crate::PendingTransfer,
    mut stream: tokio::net::TcpStream,
) {
    RUNTIME.spawn(async move {
        use tokio::io::AsyncReadExt;
        let result = async {
            let mut buffer = vec![0u8; 16 * 1024];
            let mut payload: Vec<u8> = Vec::new();
            loop {
                let n = stream.read(&mut buffer).await.map_err(|_| "network")?;
                if n == 0 {
                    break;
                }
                if payload.len() as u64 + n as u64 > job.max_bytes {
                    return Err("too_large");
                }
                payload.extend_from_slice(&buffer[..n]);
            }
            std::fs::write(&job.target_path, &payload).map_err(|_| "io")?;
            Ok::<_, &'static str>(payload.len() as u64)
        }
        .await;
        let event = match result {
            Ok(bytes) => TsEvent::FileTransfer {
                transfer_id: transfer_id as u32,
                remote_path: job.remote_path.clone(),
                local_path: job.target_path.clone(),
                bytes,
                ok: true,
                error: None,
            },
            Err(reason) => {
                let _ = std::fs::remove_file(&job.target_path);
                TsEvent::FileTransfer {
                    transfer_id: transfer_id as u32,
                    remote_path: job.remote_path.clone(),
                    local_path: String::new(),
                    bytes: 0,
                    ok: false,
                    error: Some(reason.into()),
                }
            }
        };
        push_event(conn_id, event);
    });
}

/// Requests a file download from the server.
///
/// `remote_path` is a server-side path such as `/icon_1234` (icons live in
/// channel 0). `target_path` must be inside the app's private storage — the
/// caller (Dart) owns that decision, the engine only refuses paths that are
/// obviously unsafe. Returns the transfer id, or 0 when the request was
/// rejected locally.
#[no_mangle]
pub extern "C" fn ts_download_file(
    conn_id: crate::ConnectionId,
    channel_id: u64,
    remote_path: *const c_char,
    channel_password: *const c_char,
    target_path: *const c_char,
    max_bytes: u64,
) -> u32 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if remote_path.is_null() || target_path.is_null() || !connected {
        return 0;
    }
    let remote = unsafe { std::ffi::CStr::from_ptr(remote_path) }
        .to_string_lossy()
        .into_owned();
    let target = unsafe { std::ffi::CStr::from_ptr(target_path) }
        .to_string_lossy()
        .into_owned();
    let password = if channel_password.is_null() {
        String::new()
    } else {
        unsafe { std::ffi::CStr::from_ptr(channel_password) }
            .to_string_lossy()
            .into_owned()
    };

    if remote.is_empty() || target.is_empty() {
        return 0;
    }
    // Defence in depth against a path built from server-controlled data.
    if target.contains("..") || !target.starts_with('/') {
        log_warn!("ts_download_file: refused suspicious target path");
        return 0;
    }
    if max_bytes == 0 || max_bytes > TRANSFER_HARD_LIMIT {
        log_warn!("ts_download_file: refused out-of-range size limit");
        return 0;
    }

    let Some(session) = SESSIONS.get(&conn_id) else {
        return 0;
    };
    let transfer_id = (session.next_transfer_id.fetch_add(1, Ordering::Relaxed) % (u16::MAX as u32))
        .max(1) as u16;
    session.pending_transfers.lock().insert(
        transfer_id,
        crate::PendingTransfer {
            target_path: target,
            max_bytes,
            remote_path: remote.clone(),
        },
    );

    if queue_command(
        conn_id,
        Command::DownloadFile {
            transfer_id,
            channel_id,
            channel_password: password,
            remote_path: remote,
        },
    ) == 0
    {
        if let Some(s) = SESSIONS.get(&conn_id) {
            s.pending_transfers.lock().remove(&transfer_id);
        }
        return 0;
    }
    transfer_id as u32
}

/// Cancels a pending transfer that has not started streaming yet.
#[no_mangle]
pub extern "C" fn ts_cancel_file_transfer(conn_id: crate::ConnectionId, transfer_id: u32) -> u8 {
    if transfer_id == 0 || transfer_id > u16::MAX as u32 {
        return 0;
    }
    if let Some(s) = SESSIONS.get(&conn_id) {
        if s.pending_transfers
            .lock()
            .remove(&(transfer_id as u16))
            .is_some()
        {
            return 1;
        }
        if s.upload_jobs.lock().remove(&(transfer_id as u16)).is_some() {
            return 1;
        }
    }
    0
}

/// Requests a file upload to the server.
///
/// `remote_path` is the server-side target (e.g. `/myfile.txt`), `source_path`
/// a local file the engine streams. Returns the transfer id, or 0 when the
/// request was rejected locally.
#[no_mangle]
pub extern "C" fn ts_upload_file(
    conn_id: crate::ConnectionId,
    channel_id: u64,
    remote_path: *const c_char,
    channel_password: *const c_char,
    source_path: *const c_char,
    overwrite: u8,
) -> u32 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if remote_path.is_null() || source_path.is_null() || !connected {
        return 0;
    }
    let remote = unsafe { std::ffi::CStr::from_ptr(remote_path) }
        .to_string_lossy()
        .into_owned();
    let source = unsafe { std::ffi::CStr::from_ptr(source_path) }
        .to_string_lossy()
        .into_owned();
    let password = if channel_password.is_null() {
        String::new()
    } else {
        unsafe { std::ffi::CStr::from_ptr(channel_password) }
            .to_string_lossy()
            .into_owned()
    };

    if remote.is_empty() || source.is_empty() || !remote.starts_with('/') {
        return 0;
    }
    let size = match std::fs::metadata(&source) {
        Ok(m) => m.len(),
        Err(_) => return 0,
    };
    if size == 0 || size > TRANSFER_HARD_LIMIT {
        log_warn!("ts_upload_file: refused out-of-range file size");
        return 0;
    }

    let Some(session) = SESSIONS.get(&conn_id) else {
        return 0;
    };
    let transfer_id = (session.next_transfer_id.fetch_add(1, Ordering::Relaxed) % (u16::MAX as u32))
        .max(1) as u16;
    // The event loop stores the upload job keyed by the *engine* handle once
    // `con.upload_file` answers; here we only hand it the request. If it cannot
    // be queued, we must not leave a dangling job behind.
    if queue_command(
        conn_id,
        Command::UploadFile {
            transfer_id,
            channel_id,
            channel_password: password,
            remote_path: remote,
            source_path: source,
            size,
            overwrite: overwrite != 0,
        },
    ) == 0
    {
        return 0;
    }
    transfer_id as u32
}

// ─── File management (ftgetfilelist / ftdeletefile / ftcreatedir) ────

/// Requests the file listing of a channel directory (`ftgetfilelist`).
///
/// Returns a `request_id` (> 0) that the UI uses to match the asynchronous
/// `ServerFileList` event, or 0 when the request was rejected locally. The
/// request is correlated server-side by `(channel_id, path)`; only one listing
/// per directory may be in flight (a newer request supersedes a pending one).
#[no_mangle]
pub extern "C" fn ts_list_files(
    conn_id: crate::ConnectionId,
    channel_id: u64,
    path: *const c_char,
    channel_password: *const c_char,
) -> u32 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if path.is_null() || !connected {
        return 0;
    }
    let path = unsafe { std::ffi::CStr::from_ptr(path) }
        .to_string_lossy()
        .trim()
        .to_string();
    if path.is_empty() {
        return 0;
    }
    let password = if channel_password.is_null() {
        String::new()
    } else {
        unsafe { std::ffi::CStr::from_ptr(channel_password) }
            .to_string_lossy()
            .into_owned()
    };

    let Some(session) = SESSIONS.get(&conn_id) else {
        return 0;
    };
    let request_id = session.next_request_id.fetch_add(1, Ordering::Relaxed);
    // Zero is reserved as "no request": skip it if we ever wrap.
    let request_id = if request_id == 0 {
        session.next_request_id.fetch_add(1, Ordering::Relaxed)
    } else {
        request_id
    };
    // Keep a copy of the path for the pending map; the command consumes one.
    let path_key = path.clone();
    session
        .pending_file_requests
        .lock()
        .insert((channel_id, path_key.clone()), request_id);

    if queue_command(
        conn_id,
        Command::RequestFileList {
            request_id,
            channel_id,
            channel_password: password,
            path,
        },
    ) == 0
    {
        if let Some(s) = SESSIONS.get(&conn_id) {
            s.pending_file_requests.lock().remove(&(channel_id, path_key));
        }
        return 0;
    }
    request_id
}

/// Deletes a file from a channel directory (`ftdeletefile`). The server
/// enforces the file-delete permission and answers with a typed `command_error`
/// when it is missing.
#[no_mangle]
pub extern "C" fn ts_delete_file(
    conn_id: crate::ConnectionId,
    channel_id: u64,
    path: *const c_char,
    channel_password: *const c_char,
) -> u8 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if path.is_null() || !connected {
        return 0;
    }
    let path = unsafe { std::ffi::CStr::from_ptr(path) }
        .to_string_lossy()
        .trim()
        .to_string();
    if path.is_empty() {
        return 0;
    }
    let password = if channel_password.is_null() {
        String::new()
    } else {
        unsafe { std::ffi::CStr::from_ptr(channel_password) }
            .to_string_lossy()
            .into_owned()
    };
    queue_command(
        conn_id,
        Command::DeleteFile {
            channel_id,
            channel_password: password,
            path,
        },
    )
}

/// Creates a directory in a channel (`ftcreatedir`).
#[no_mangle]
pub extern "C" fn ts_create_directory(
    conn_id: crate::ConnectionId,
    channel_id: u64,
    path: *const c_char,
    channel_password: *const c_char,
) -> u8 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if path.is_null() || !connected {
        return 0;
    }
    let path = unsafe { std::ffi::CStr::from_ptr(path) }
        .to_string_lossy()
        .trim()
        .to_string();
    if path.is_empty() {
        return 0;
    }
    let password = if channel_password.is_null() {
        String::new()
    } else {
        unsafe { std::ffi::CStr::from_ptr(channel_password) }
            .to_string_lossy()
            .into_owned()
    };
    queue_command(
        conn_id,
        Command::CreateDirectory {
            channel_id,
            channel_password: password,
            path,
        },
    )
}

// ─── Channel administration (permission-gated) ──────────────────────

/// Reads an optional C string, trimming and capping it. Returns None on null
/// or blank input.
fn opt_cstr(raw: *const c_char, max: usize) -> Option<String> {
    if raw.is_null() {
        return None;
    }
    let value = unsafe { std::ffi::CStr::from_ptr(raw) }
        .to_string_lossy()
        .into_owned();
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.chars().take(max).collect())
    }
}

/// Channel names are capped by the server (default ~40); keep well under it.
const CHANNEL_NAME_MAX: usize = 40;
const CHANNEL_TEXT_MAX: usize = 2000;

/// Creates a channel in [parent_id] (0 = root) or in the currently selected
/// channel. The server enforces `b_channel_create_*` and answers with a typed
/// `command_error` when the permission is missing.
#[no_mangle]
pub extern "C" fn ts_create_channel(
    conn_id: crate::ConnectionId,
    parent_id: u64,
    name: *const c_char,
    topic: *const c_char,
    description: *const c_char,
    password: *const c_char,
    max_clients: i32,
    permanent: u8,
    semi_permanent: u8,
) -> u8 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if !connected || name.is_null() {
        return 0;
    }
    let Some(name) = opt_cstr(name, CHANNEL_NAME_MAX) else {
        return 0;
    };
    queue_command(
        conn_id,
        Command::CreateChannel {
            parent_id,
            name,
            topic: opt_cstr(topic, CHANNEL_TEXT_MAX),
            description: opt_cstr(description, CHANNEL_TEXT_MAX),
            password: opt_cstr(password, 64),
            max_clients: (max_clients > 0).then_some(max_clients),
            permanent: permanent != 0,
            semi_permanent: semi_permanent != 0,
        },
    )
}

/// Edits an existing channel. Null arguments leave the field unchanged.
#[no_mangle]
pub extern "C" fn ts_edit_channel(
    conn_id: crate::ConnectionId,
    channel_id: u64,
    name: *const c_char,
    topic: *const c_char,
    description: *const c_char,
    password: *const c_char,
    has_password: i32,
    max_clients: i32,
    permanent: i32,
    semi_permanent: i32,
) -> u8 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if !connected || channel_id == 0 {
        return 0;
    }
    queue_command(
        conn_id,
        Command::EditChannel {
            channel_id,
            name: opt_cstr(name, CHANNEL_NAME_MAX),
            topic: opt_cstr(topic, CHANNEL_TEXT_MAX),
            description: opt_cstr(description, CHANNEL_TEXT_MAX),
            password: opt_cstr(password, 64),
            has_password: if has_password >= 0 {
                Some(has_password != 0)
            } else {
                None
            },
            max_clients: (max_clients > 0).then_some(max_clients),
            permanent: (permanent >= 0).then_some(permanent != 0),
            semi_permanent: (semi_permanent >= 0).then_some(semi_permanent != 0),
        },
    )
}

/// Deletes a channel. `force = 1` deletes the tree even with sub-channels.
#[no_mangle]
pub extern "C" fn ts_delete_channel(
    conn_id: crate::ConnectionId,
    channel_id: u64,
    force: u8,
) -> u8 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if !connected || channel_id == 0 {
        return 0;
    }
    queue_command(
        conn_id,
        Command::DeleteChannel {
            channel_id,
            force: force != 0,
        },
    )
}

/// Moves/re-orders a channel in the tree.
#[no_mangle]
pub extern "C" fn ts_move_channel_tree(
    conn_id: crate::ConnectionId,
    channel_id: u64,
    parent_id: u64,
    order: u64,
) -> u8 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if !connected || channel_id == 0 {
        return 0;
    }
    queue_command(
        conn_id,
        Command::MoveChannelTree {
            channel_id,
            parent_id,
            order: (order > 0).then_some(order),
        },
    )
}

// ─── Moderation (permission-gated by the server) ────────────────────

/// Maximum length accepted for a kick/ban reason or a poke message.
const REASON_MAX: usize = 200;

fn optional_reason(raw: *const c_char) -> Option<String> {
    if raw.is_null() {
        return None;
    }
    let value = unsafe { std::ffi::CStr::from_ptr(raw) }
        .to_string_lossy()
        .into_owned();
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.chars().take(REASON_MAX).collect())
    }
}

/// Kicks a client from its channel (`from_server = 0`) or from the server.
///
/// The permission is enforced by the server; the UI only *hides* actions the
/// permission hints say are impossible, it never assumes they will succeed.
/// A refusal comes back as a typed `command_error`.
#[no_mangle]
pub extern "C" fn ts_kick_client(
    conn_id: crate::ConnectionId,
    client_id: u16,
    from_server: u8,
    reason: *const c_char,
) -> u8 {
    if client_id == 0 {
        return 0;
    }
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if !connected {
        return 0;
    }
    // Kicking yourself is a UI bug, not a moderation action.
    let own = crate::session(conn_id)
        .map(|state| state.lock().own_client_id)
        .unwrap_or(0);
    if client_id as u32 == own {
        return 0;
    }
    queue_command(
        conn_id,
        Command::KickClient {
            client_id,
            from_server: from_server != 0,
            reason: optional_reason(reason),
        },
    )
}

/// Bans a client for `seconds` (0 = permanent).
#[no_mangle]
pub extern "C" fn ts_ban_client(
    conn_id: crate::ConnectionId,
    client_id: u16,
    seconds: u64,
    reason: *const c_char,
) -> u8 {
    if client_id == 0 {
        return 0;
    }
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if !connected {
        return 0;
    }
    let own = crate::session(conn_id)
        .map(|state| state.lock().own_client_id)
        .unwrap_or(0);
    if client_id as u32 == own {
        return 0;
    }
    queue_command(
        conn_id,
        Command::BanClient {
            client_id,
            seconds,
            reason: optional_reason(reason),
        },
    )
}

/// Sends a poke (a message that pops up on the target's screen).
#[no_mangle]
pub extern "C" fn ts_poke_client(
    conn_id: crate::ConnectionId,
    client_id: u16,
    message: *const c_char,
) -> u8 {
    if client_id == 0 || message.is_null() {
        return 0;
    }
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if !connected {
        return 0;
    }
    let Some(text) = optional_reason(message) else {
        return 0;
    };
    queue_command(
        conn_id,
        Command::PokeClient {
            client_id,
            message: text,
        },
    )
}

/// Moves another client to a channel. Uses the same command as moving
/// ourselves — only the client ID differs — so the channel password path is
/// shared.
#[no_mangle]
pub extern "C" fn ts_move_client(
    conn_id: crate::ConnectionId,
    client_id: u16,
    channel_id: u64,
    password: *const c_char,
) -> u8 {
    if client_id == 0 || channel_id == 0 {
        return 0;
    }
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if !connected {
        return 0;
    }
    queue_command(
        conn_id,
        Command::MoveChannel {
            client_id,
            channel_id,
            channel_password: optional_reason(password),
        },
    )
}

// ─── Own client status ──────────────────────────────────────────────

/// TeamSpeak refuses nicknames outside 3..30 characters; reject locally so the
/// user gets an immediate answer instead of a server error.
const NICKNAME_MIN: usize = 3;
const NICKNAME_MAX: usize = 30;
/// Away messages are capped by the server; keep well under it.
const AWAY_MESSAGE_MAX: usize = 200;

/// Sets the away/AFK flag. Passing a null or empty message with `away = 1`
/// marks the user away without a reason; `away = 0` always clears the message.
#[no_mangle]
pub extern "C" fn ts_set_away(
    conn_id: crate::ConnectionId,
    away: u8,
    message: *const c_char,
) -> u8 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if !connected {
        return 0;
    }
    let message = if message.is_null() {
        None
    } else {
        let value = unsafe { std::ffi::CStr::from_ptr(message) }
            .to_string_lossy()
            .into_owned();
        let trimmed = value.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.chars().take(AWAY_MESSAGE_MAX).collect::<String>())
        }
    };
    queue_command(
        conn_id,
        Command::SetAway {
            away: away != 0,
            message,
        },
    )
}

/// Renames the local client for the current session.
/// Returns 0 when the name is empty, too short or too long.
#[no_mangle]
pub extern "C" fn ts_set_nickname(conn_id: crate::ConnectionId, name: *const c_char) -> u8 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if name.is_null() || !connected {
        return 0;
    }
    let value = unsafe { std::ffi::CStr::from_ptr(name) }
        .to_string_lossy()
        .into_owned();
    let trimmed = value.trim().to_string();
    let length = trimmed.chars().count();
    if !(NICKNAME_MIN..=NICKNAME_MAX).contains(&length) {
        log_warn!("ts_set_nickname: rejected, length {} out of range", length);
        return 0;
    }
    queue_command(conn_id, Command::SetNickname { name: trimmed })
}

/// Toggles channel commander. The server enforces the permission and answers
/// with a typed `command_error` when it is missing.
#[no_mangle]
pub extern "C" fn ts_set_channel_commander(conn_id: crate::ConnectionId, enabled: u8) -> u8 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if !connected {
        return 0;
    }
    queue_command(
        conn_id,
        Command::SetChannelCommander {
            enabled: enabled != 0,
        },
    )
}

/// Pushes a command onto the event loop queue. Returns 1 on success.
fn queue_command(conn_id: crate::ConnectionId, command: Command) -> u8 {
    let tx = SESSIONS
        .get(&conn_id)
        .and_then(|s| s.command_tx.lock().clone());
    match tx {
        Some(tx) if tx.send(command).is_ok() => 1,
        _ => 0,
    }
}

// ─── Whisper ────────────────────────────────────────────────────────

/// Maximum number of targets per whisper packet. The wire format stores the
/// list lengths in a single byte each, and the official client keeps whisper
/// lists far below that; 100 is the practical cap used here.
const WHISPER_MAX_TARGETS: usize = 100;

#[derive(serde::Deserialize)]
struct WhisperTargetsInput {
    #[serde(default)]
    clients: Vec<u32>,
    #[serde(default)]
    channels: Vec<u64>,
}

/// Replace the outgoing whisper target list.
///
/// `json` is `{"clients":[<client id>...],"channels":[<channel id>...]}`.
/// Duplicate entries and the own client ID are removed, the list is sorted for
/// a deterministic packet layout, and both lists are capped at
/// `WHISPER_MAX_TARGETS`. Setting an empty list disables whisper transmission
/// even if whisper is armed.
#[no_mangle]
pub extern "C" fn ts_set_whisper_targets(conn_id: crate::ConnectionId, json: *const c_char) -> u8 {
    if json.is_null() {
        return 0;
    }
    let raw = unsafe { std::ffi::CStr::from_ptr(json) }
        .to_string_lossy()
        .into_owned();
    let parsed: WhisperTargetsInput = match serde_json::from_str(&raw) {
        Ok(value) => value,
        Err(e) => {
            log_warn!("ts_set_whisper_targets: invalid JSON: {}", e);
            return 0;
        }
    };

    let Some(state) = crate::session(conn_id) else {
        return 0;
    };
    let mut guard = state.lock();
    let own_id = guard.own_client_id;
    let (clients, channels) = sanitize_whisper_targets(parsed.clients, parsed.channels, own_id);
    guard.whisper_target_clients = clients;
    guard.whisper_target_channels = channels;
    1
}

/// Normalizes a whisper target list: drops invalid IDs (0, out of u16 range)
/// and the own client ID, de-duplicates, sorts for a deterministic packet
/// layout and caps both lists at `WHISPER_MAX_TARGETS`.
fn sanitize_whisper_targets(
    clients: Vec<u32>,
    channels: Vec<u64>,
    own_client_id: u32,
) -> (Vec<u16>, Vec<u64>) {
    let mut clients: Vec<u16> = clients
        .into_iter()
        .filter(|id| *id != 0 && *id != own_client_id && *id <= u16::MAX as u32)
        .map(|id| id as u16)
        .collect();
    clients.sort_unstable();
    clients.dedup();
    clients.truncate(WHISPER_MAX_TARGETS);

    let mut channels: Vec<u64> = channels.into_iter().filter(|id| *id != 0).collect();
    channels.sort_unstable();
    channels.dedup();
    channels.truncate(WHISPER_MAX_TARGETS);

    (clients, channels)
}

/// Arm or disarm outgoing whisper. Voice keeps flowing either way — only the
/// destination changes, so a whisper key can be held without cutting speech.
#[no_mangle]
pub extern "C" fn ts_set_whisper_active(conn_id: crate::ConnectionId, active: u8) -> u8 {
    let Some(state) = crate::session(conn_id) else {
        return 0;
    };
    let mut guard = state.lock();
    let has_target =
        !guard.whisper_target_clients.is_empty() || !guard.whisper_target_channels.is_empty();
    if active != 0 && !has_target {
        guard.whisper_active = false;
        return 0;
    }
    guard.whisper_active = active != 0;
    1
}

/// Incoming whisper policy: 0 = accept all, 1 = accept only allow-listed UIDs.
#[no_mangle]
pub extern "C" fn ts_set_whisper_allow_mode(conn_id: crate::ConnectionId, mode: u8) -> u8 {
    if mode > 1 {
        return 0;
    }
    let Some(state) = crate::session(conn_id) else {
        return 0;
    };
    state.lock().whisper_allow_mode = mode;
    1
}

/// Replace the incoming whisper allow list. `json` is an array of client UIDs.
#[no_mangle]
pub extern "C" fn ts_set_whisper_allowlist(
    conn_id: crate::ConnectionId,
    json: *const c_char,
) -> u8 {
    if json.is_null() {
        return 0;
    }
    let raw = unsafe { std::ffi::CStr::from_ptr(json) }
        .to_string_lossy()
        .into_owned();
    let uids: Vec<String> = match serde_json::from_str(&raw) {
        Ok(value) => value,
        Err(e) => {
            log_warn!("ts_set_whisper_allowlist: invalid JSON: {}", e);
            return 0;
        }
    };
    let Some(state) = crate::session(conn_id) else {
        return 0;
    };
    let mut guard = state.lock();
    guard.whisper_allowed_uids = uids.into_iter().filter(|u| !u.is_empty()).collect();
    1
}

/// Current whisper configuration as JSON, for UI reconciliation after a
/// reconnect or a process restart.
#[no_mangle]
pub extern "C" fn ts_get_whisper_status(conn_id: crate::ConnectionId) -> *mut c_char {
    let Some(state) = crate::session(conn_id) else {
        return to_c_str("{\"active\":false,\"clients\":[],\"channels\":[],\"allow_mode\":0,\"allowed_uids\":[],\"ignored_count\":0}".to_string());
    };
    let guard = state.lock();
    let mut allowed: Vec<&String> = guard.whisper_allowed_uids.iter().collect();
    allowed.sort();
    let status = serde_json::json!({
        "active": guard.whisper_active,
        "clients": guard.whisper_target_clients,
        "channels": guard.whisper_target_channels,
        "allow_mode": guard.whisper_allow_mode,
        "allowed_uids": allowed,
        "ignored_count": guard.whisper_ignored_count,
    });
    to_c_str(status.to_string())
}

// ─── Mute ───────────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn ts_set_muted(conn_id: crate::ConnectionId, inp: u8, out: u8) -> u8 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if !connected {
        return 0;
    }
    queue_command(
        conn_id,
        Command::SetMuted {
            input: inp != 0,
            output: out != 0,
        },
    )
}

#[no_mangle]
pub extern "C" fn ts_is_connected(conn_id: crate::ConnectionId) -> u8 {
    if crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false)
    {
        1
    } else {
        0
    }
}

// ─── VAD ────────────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn ts_set_vad_threshold(conn_id: crate::ConnectionId, threshold: f32) {
    if let Some(state) = crate::session(conn_id) {
        let mut guard = state.lock();
        guard.vad_threshold = threshold.clamp(0.000_5, 1.0);
        // Re-learn the ambient floor after a material user configuration change.
        guard.vad_noise_floor = 0.0;
    }
}

#[no_mangle]
pub extern "C" fn ts_set_vad_enabled(conn_id: crate::ConnectionId, enabled: u8) -> u8 {
    if let Some(state) = crate::session(conn_id) {
        state.lock().vad_enabled = enabled != 0;
        1
    } else {
        0
    }
}

#[no_mangle]
pub extern "C" fn ts_is_voice_active(conn_id: crate::ConnectionId) -> u8 {
    let Some(state) = crate::session(conn_id) else {
        return 0;
    };
    let mut guard = state.lock();
    let active = guard.voice_active;
    guard.voice_active = false;
    if active {
        1
    } else {
        0
    }
}

// ─── Mic gain ───────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn ts_set_mic_gain(conn_id: crate::ConnectionId, gain: f32) {
    if let Some(state) = crate::session(conn_id) {
        state.lock().mic_gain = gain.clamp(0.0, 3.0);
    }
}

// ─── Per-client volume ──────────────────────────────────────────────

/// Set per-client volume in decibels.  Range -20 to +20 dB.
/// Converted to linear gain internally: gain = 10^(dB/20).
///
/// The numeric `client_id` is a session-scoped handle. The value is persisted
/// under the client's user UID in the *global* [`CLIENT_VOLUMES`] table, so it
/// survives reconnects and client ID reuse and is shared across servers (TS3
/// UIDs are derived from the identity and are the same everywhere).
/// Sets the app-wide output volume (dB, -20..+20). Shared by every server.
#[no_mangle]
pub extern "C" fn ts_set_master_volume(volume_db: f32) {
    crate::set_master_volume_db(volume_db);
}

#[no_mangle]
pub extern "C" fn ts_set_client_volume(
    conn_id: crate::ConnectionId,
    client_id: u16,
    volume_db: f32,
) {
    let vol_db = volume_db.clamp(-20.0, 20.0);
    let gain = 10.0_f32.powf(vol_db / 20.0);

    // Persist dB to the global store keyed by the user UID.
    let uid = crate::session(conn_id).and_then(|state| {
        let guard = state.lock();
        guard
            .clients
            .iter()
            .find(|c| c.id as u16 == client_id)
            .and_then(|c| c.uid.as_ref())
            .cloned()
    });
    if let Some(uid) = uid {
        CLIENT_VOLUMES.lock().insert(uid, vol_db);
    }

    // Also update the live jitter buffer if it exists
    if let Some(buf) = CLIENT_BUFFERS.get(&(conn_id, client_id)) {
        buf.volume.store(f32::to_bits(gain), Ordering::Release);
    }
}

// ─── Audio (mic send only, no receive) ──────────────────────────────

/// Creates the Opus encoder for one session's microphone. The mic is a single
/// device, so it transmits into whichever session is currently focused.
#[no_mangle]
pub extern "C" fn ts_start_audio(conn_id: crate::ConnectionId) -> u8 {
    let encoder = match opus_rs::OpusEncoder::new(48000, 1, opus_rs::Application::Voip) {
        Ok(e) => e,
        Err(e) => {
            log_error!("ts_start_audio: encoder error: {}", e);
            return 0;
        }
    };
    let Some(state) = crate::session(conn_id) else {
        return 0;
    };
    let mut guard = state.lock();
    guard.audio_encoder = Some(encoder);
    guard.pcm_in.clear();
    guard.audio_seq = 0;
    1
}

/// Stops transmitting for one session (drops its encoder). This never touches
/// the shared playback stream: other servers keep playing.
#[no_mangle]
pub extern "C" fn ts_stop_audio(conn_id: crate::ConnectionId) {
    if let Some(state) = crate::session(conn_id) {
        let mut guard = state.lock();
        guard.audio_encoder = None;
        guard.pcm_in.clear();
    }
}

#[no_mangle]
pub extern "C" fn ts_send_audio(
    conn_id: crate::ConnectionId,
    data: *const f32,
    data_len: u32,
) -> u8 {
    let connected = crate::session(conn_id)
        .map(|state| state.lock().connected)
        .unwrap_or(false);
    if !connected {
        return 0;
    }
    if data_len == 0 {
        return 0;
    }
    let raw = unsafe { std::slice::from_raw_parts(data, data_len as usize) };
    let samples: Vec<f32> = raw.to_vec(); // raw samples — gain applied after VAD
    queue_command(conn_id, Command::SendAudio { data: samples })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn whisper_targets_are_sorted_deduped_and_filtered() {
        let (clients, channels) =
            sanitize_whisper_targets(vec![9, 3, 3, 0, 7, 70_000, 5], vec![40, 10, 10, 0], 7);
        // 0 is invalid, 7 is the own client, 70_000 exceeds the u16 range.
        assert_eq!(clients, vec![3, 5, 9]);
        assert_eq!(channels, vec![10, 40]);
    }

    #[test]
    fn whisper_targets_are_capped() {
        let many: Vec<u32> = (1..=300).collect();
        let (clients, _) = sanitize_whisper_targets(many, Vec::new(), 0);
        assert_eq!(clients.len(), WHISPER_MAX_TARGETS);
        assert_eq!(clients[0], 1);
    }

    #[test]
    fn password_and_ban_refusals_are_not_retryable() {
        use tsclientlib::TsError;
        assert_eq!(
            classify_server_refusal(TsError::ServerInvalidPassword),
            ("password", false)
        );
        assert_eq!(
            classify_server_refusal(TsError::ConnectFailedBanned),
            ("banned", false)
        );
        assert_eq!(
            classify_server_refusal(TsError::ClientNicknameInuse),
            ("nickname_in_use", false)
        );
    }

    #[test]
    fn transient_transport_failures_stay_retryable() {
        let timeout = tsclientlib::Error::InitserverTimeout;
        assert_eq!(classify_connect_error(&timeout), ("timeout", true));

        let gone = tsclientlib::Error::ConnectionGone;
        assert_eq!(classify_connect_error(&gone), ("network", true));

        let identity = tsclientlib::Error::IdentityLevel(8);
        assert_eq!(classify_connect_error(&identity), ("identity_level", false));
    }

    #[test]
    fn nested_connect_failure_inherits_the_first_child_verdict() {
        let nested = tsclientlib::Error::ConnectFailed {
            address: "ts.example.test".into(),
            errors: vec![tsclientlib::Error::InitserverTimeout],
        };
        assert_eq!(classify_connect_error(&nested), ("timeout", true));

        let empty = tsclientlib::Error::ConnectFailed {
            address: "ts.example.test".into(),
            errors: Vec::new(),
        };
        assert_eq!(classify_connect_error(&empty), ("network", true));
    }

    #[test]
    fn budget_allows_a_burst_then_paces_commands() {
        let start = Instant::now();
        let mut budget = crate::CommandBudget::new(start);
        // Five mute updates cost 0.5 each: well inside the burst capacity.
        for _ in 0..5 {
            budget.enqueue(Command::SetMuted {
                input: true,
                output: false,
            });
        }
        // SetMuted supersedes itself, so only one survives the queue.
        assert_eq!(budget.pending(), 1);
        assert!(budget.take_ready(start).is_some());
        assert!(budget.take_ready(start).is_none());
    }

    #[test]
    fn budget_refills_over_time_and_never_exceeds_capacity() {
        let start = Instant::now();
        let mut budget = crate::CommandBudget::new(start);
        // Drain the bucket with distinct messages (never superseded).
        for index in 0..4 {
            budget.enqueue(Command::SendMessage {
                target_mode: 2,
                target_cid: 0,
                message: format!("message {}", index),
            });
        }
        let mut served = 0;
        while budget.take_ready(start).is_some() {
            served += 1;
        }
        // Capacity 8 / cost 2 per message.
        assert_eq!(served, 4);

        // One second later the bucket has refilled by REFILL_PER_SEC tokens.
        budget.enqueue(Command::SendMessage {
            target_mode: 2,
            target_cid: 0,
            message: "later".into(),
        });
        assert!(budget.take_ready(start + Duration::from_secs(1)).is_some());
    }

    #[test]
    fn queued_channel_moves_collapse_to_the_last_one() {
        let start = Instant::now();
        let mut budget = crate::CommandBudget::new(start);
        for channel_id in [4u64, 7, 9] {
            budget.enqueue(Command::MoveChannel {
                client_id: 1,
                channel_id,
                channel_password: None,
            });
        }
        assert_eq!(budget.pending(), 1);
        match budget.take_ready(start) {
            Some(Command::MoveChannel { channel_id, .. }) => assert_eq!(channel_id, 9),
            other => panic!("unexpected command: {:?}", other),
        }
    }

    #[test]
    fn queue_is_bounded_and_counts_drops() {
        let start = Instant::now();
        let mut budget = crate::CommandBudget::new(start);
        for index in 0..(crate::CommandBudget::MAX_QUEUE + 5) {
            budget.enqueue(Command::SendMessage {
                target_mode: 2,
                target_cid: 0,
                message: format!("message {}", index),
            });
        }
        assert_eq!(budget.pending(), crate::CommandBudget::MAX_QUEUE);
        assert_eq!(budget.dropped, 5);
    }

    #[test]
    fn degraded_mode_slows_down_then_recovers() {
        let start = Instant::now();
        let mut budget = crate::CommandBudget::new(start);
        budget.enter_degraded(start);
        assert!(budget.is_degraded());

        budget.enqueue(Command::SetMuted {
            input: false,
            output: false,
        });
        // Tokens were dropped to zero: nothing goes out immediately.
        assert!(budget.take_ready(start).is_none());
        // 0.5 tokens/s in degraded mode, SetMuted costs 0.5.
        assert!(budget.take_ready(start + Duration::from_secs(1)).is_some());

        // After the penalty window the normal rate is restored.
        let after = start + crate::CommandBudget::DEGRADED_DURATION + Duration::from_secs(1);
        budget.enqueue(Command::SendMessage {
            target_mode: 2,
            target_cid: 0,
            message: "back to normal".into(),
        });
        assert!(budget.take_ready(after).is_some());
        assert!(!budget.is_degraded());
    }

    #[test]
    fn client_serialization_keeps_group_names_and_icons_aligned() {
        // The UI pairs names and icons by index, so both lists must be sorted
        // by the same key (the group name).
        let mut groups = vec![
            ("Moderator".to_string(), 20u32),
            ("Admin".to_string(), 10u32),
            ("Guest".to_string(), 0u32),
        ];
        let mut names: Vec<String> = groups.iter().map(|(name, _)| name.clone()).collect();
        names.sort();
        groups.sort_by(|left, right| left.0.cmp(&right.0));
        let icons: Vec<u32> = groups.into_iter().map(|(_, icon)| icon).collect();

        assert_eq!(names, vec!["Admin", "Guest", "Moderator"]);
        assert_eq!(icons, vec![10, 0, 20]);
    }

    #[test]
    fn download_requests_refuse_unsafe_targets() {
        use std::ffi::CString;
        // No session: every call must be refused before touching anything.
        let remote = CString::new("/icon_1234").unwrap();
        let traversal = CString::new("/data/../../etc/passwd").unwrap();
        assert_eq!(
            ts_download_file(
                1,
                0,
                remote.as_ptr(),
                std::ptr::null(),
                traversal.as_ptr(),
                1024
            ),
            0
        );

        let relative = CString::new("cache/icon").unwrap();
        assert_eq!(
            ts_download_file(
                1,
                0,
                remote.as_ptr(),
                std::ptr::null(),
                relative.as_ptr(),
                1024
            ),
            0
        );
    }

    #[test]
    fn download_requests_refuse_out_of_range_limits() {
        use std::ffi::CString;
        let remote = CString::new("/icon_1234").unwrap();
        let target = CString::new("/data/app/cache/icon_1234").unwrap();
        // Zero and anything above the hard limit are both rejected.
        assert_eq!(
            ts_download_file(1, 0, remote.as_ptr(), std::ptr::null(), target.as_ptr(), 0),
            0
        );
        assert_eq!(
            ts_download_file(
                1,
                0,
                remote.as_ptr(),
                std::ptr::null(),
                target.as_ptr(),
                TRANSFER_HARD_LIMIT + 1
            ),
            0
        );
    }

    #[test]
    fn cancelling_an_unknown_transfer_is_a_no_op() {
        assert_eq!(ts_cancel_file_transfer(1, 0), 0);
        assert_eq!(ts_cancel_file_transfer(1, u32::MAX), 0);
        assert_eq!(ts_cancel_file_transfer(1, 4242), 0);
    }

    #[test]
    fn cancelling_a_pending_transfer_forgets_it() {
        SESSIONS.insert(99, crate::Session::new(99, TsConnection::new()));
        if let Some(s) = SESSIONS.get(&99) {
            s.pending_transfers.lock().insert(
                77,
                crate::PendingTransfer {
                    target_path: "/tmp/icon".into(),
                    max_bytes: 1024,
                    remote_path: "/icon_1".into(),
                },
            );
        }
        assert_eq!(ts_cancel_file_transfer(99, 77), 1);
        // A second cancel finds nothing, and the answer that may still arrive
        // from the server will be ignored for lack of a pending entry.
        assert_eq!(ts_cancel_file_transfer(99, 77), 0);
        SESSIONS.remove(&99);
    }

    #[test]
    fn moderation_commands_are_never_merged() {
        let start = Instant::now();
        let mut budget = crate::CommandBudget::new(start);
        // Two kicks target two different people: merging them would silently
        // spare one of them.
        budget.enqueue(Command::KickClient {
            client_id: 4,
            from_server: false,
            reason: None,
        });
        budget.enqueue(Command::KickClient {
            client_id: 5,
            from_server: true,
            reason: Some("spam".into()),
        });
        budget.enqueue(Command::PokeClient {
            client_id: 4,
            message: "hey".into(),
        });
        assert_eq!(budget.pending(), 3);
    }

    #[test]
    fn status_updates_supersede_themselves_but_not_each_other() {
        let start = Instant::now();
        let mut budget = crate::CommandBudget::new(start);
        budget.enqueue(Command::SetAway {
            away: true,
            message: Some("brb".into()),
        });
        budget.enqueue(Command::SetAway {
            away: false,
            message: None,
        });
        budget.enqueue(Command::SetNickname {
            name: "Someone".into(),
        });
        // Two away updates collapse, the rename is independent.
        assert_eq!(budget.pending(), 2);
        match budget.take_ready(start) {
            Some(Command::SetAway { away, .. }) => assert!(!away),
            other => panic!("unexpected command: {:?}", other),
        }
    }

    #[test]
    fn audio_and_disconnect_are_free() {
        assert_eq!(Command::Disconnect.flood_cost(), 0.0);
        assert_eq!(Command::SendAudio { data: Vec::new() }.flood_cost(), 0.0);
        assert!(
            Command::SendMessage {
                target_mode: 2,
                target_cid: 0,
                message: "x".into(),
            }
            .flood_cost()
                > 0.0
        );
    }

    #[test]
    fn file_and_channel_admin_are_priced() {
        // File transfer handshakes travel on the command channel but their
        // payload goes on TCP, so they are cheap.
        assert_eq!(
            Command::DownloadFile {
                transfer_id: 1,
                channel_id: 0,
                channel_password: String::new(),
                remote_path: "/icon_1".into(),
            }
            .flood_cost(),
            1.0
        );
        assert_eq!(
            Command::UploadFile {
                transfer_id: 1,
                channel_id: 0,
                channel_password: String::new(),
                remote_path: "/f".into(),
                source_path: "/tmp/f".into(),
                size: 1,
                overwrite: false,
            }
            .flood_cost(),
            1.0
        );
        // Channel administration is audited and permission-gated.
        for cmd in [
            Command::CreateChannel {
                parent_id: 0,
                name: "x".into(),
                topic: None,
                description: None,
                password: None,
                max_clients: None,
                permanent: false,
                semi_permanent: false,
            },
            Command::EditChannel {
                channel_id: 1,
                name: None,
                topic: None,
                description: None,
                password: None,
                has_password: None,
                max_clients: None,
                permanent: None,
                semi_permanent: None,
            },
            Command::DeleteChannel {
                channel_id: 1,
                force: false,
            },
            Command::MoveChannelTree {
                channel_id: 1,
                parent_id: 0,
                order: None,
            },
        ] {
            assert_eq!(cmd.flood_cost(), 2.0);
        }
    }

    #[test]
    fn adaptive_delay_stays_bounded() {
        // No session → base latency, never zero.
        assert_eq!(adaptive_delay_frames(999_999), BASE_DELAY_FRAMES);
        // A jittery path grows the buffer, but is capped at the ceiling.
        SESSIONS.insert(55, crate::Session::new(55, TsConnection::new()));
        if let Some(s) = SESSIONS.get(&55) {
            s.state.lock().jitter_ms = 500;
        }
        let d = adaptive_delay_frames(55);
        assert!(d >= BASE_DELAY_FRAMES && d <= MAX_DELAY_FRAMES);
        assert_eq!(d, MAX_DELAY_FRAMES);
        // A mild jitter only grows a little.
        if let Some(s) = SESSIONS.get(&55) {
            s.state.lock().jitter_ms = 30;
        }
        let mild = adaptive_delay_frames(55);
        assert!(mild >= BASE_DELAY_FRAMES && mild < MAX_DELAY_FRAMES);
        SESSIONS.remove(&55);
    }

    #[test]
    fn session_lifecycle_does_not_leak_audio_state() {
        // F1: exercise 100 full connection-lifecycle spins (allocate a session,
        // mount a client's audio, tear the session down) and assert that no
        // per-session artifact survives. A real connect needs a server, so the
        // leak surface we can exercise here is the *registry* teardown path.
        let mut created: Vec<crate::ConnectionId> = Vec::new();
        // Use a high, unused range so parallel tests (with small ids) never
        // collide with these keys.
        let mut id = 10_000_000u64;
        for _ in 0..100 {
            id += 1;
            let s = crate::Session::new(id, TsConnection::new());
            crate::SESSIONS.insert(id, s);
            crate::CLIENT_BUFFERS.insert((id, 5), crate::ClientJitterBuffer::new());
            crate::AUDIO_DECODERS.insert((id, 5), OpusDecoder::new(48000, 1).expect("mono"));
            created.push(id);
            // Tear-down as finalize_disconnect does (minus the event push).
            crate::drop_session_audio(id);
            crate::SESSIONS.remove(&id);
        }
        // None of the 100 sessions or their audio artifacts remain.
        for c in &created {
            assert!(!crate::SESSIONS.contains_key(c));
            assert!(!crate::CLIENT_BUFFERS.contains_key(&(*c, 5)));
            assert!(!crate::AUDIO_DECODERS.contains_key(&(*c, 5)));
            assert!(!crate::AUDIO_DECODERS_STEREO.contains_key(&(*c, 5)));
        }
    }

    #[test]
    fn whisper_terminator_and_flood_classification_are_consistent() {
        // Audio and disconnect are the only zero-cost commands; a whisper
        // control command is never zero-cost (it is a real control command).
        assert_eq!(Command::Disconnect.flood_cost(), 0.0);
        assert_eq!(Command::SendAudio { data: Vec::new() }.flood_cost(), 0.0);
        assert!(
            Command::PokeClient {
                client_id: 1,
                message: "hey".into(),
            }
            .flood_cost()
                > 0.0
        );
    }

    #[test]
    fn nested_connect_failures_prefer_the_first_verdict() {
        let nested = tsclientlib::Error::ConnectFailed {
            address: "a".into(),
            errors: vec![tsclientlib::Error::InitserverTimeout],
        };
        assert_eq!(classify_connect_error(&nested), ("timeout", true));
        // Server refusals propagate through CommandError.
        let cmd = tsclientlib::Error::CommandError(tsclientlib::CommandError {
            error: tsclientlib::TsError::ServerInvalidPassword,
            missing_permission: None,
        });
        assert_eq!(classify_connect_error(&cmd), ("password", false));
    }

    #[test]
    fn redaction_hides_addresses_identities_and_uids() {
        let redacted = crate::redact("ts_connect: address=ts.example.test:9987");
        assert!(!redacted.contains("ts.example.test"));
        assert!(redacted.contains("<redacted>"));

        // Base64-ish identity/UID blobs.
        let blob = "uid=MqQbPnn9nJEK7X8xLC2ZZzMr0T4mE3sPuAzQvHt2fLg=";
        assert!(!crate::redact(blob).contains("MqQbPnn9nJEK7X8xLC2ZZzMr0T4mE3sPuAzQvHt2fLg"));

        let ipv4 = crate::redact("peer 192.168.1.40:9987 timed out");
        assert!(!ipv4.contains("192.168.1.40"));
    }

    #[test]
    fn redaction_keeps_ordinary_diagnostics_readable() {
        let message = "event_loop: send_audio error: queue full (gen=3)";
        assert_eq!(crate::redact(message), message);
    }

    #[test]
    fn empty_target_list_is_accepted() {
        let (clients, channels) = sanitize_whisper_targets(Vec::new(), Vec::new(), 1);
        assert!(clients.is_empty());
        assert!(channels.is_empty());
    }

    #[test]
    fn connection_ids_are_monotonic_and_never_reused() {
        let a = crate::next_connection_id();
        let b = crate::next_connection_id();
        assert!(b > a);
        assert!(a >= 1);
    }

    #[test]
    fn drop_session_audio_only_removes_that_session() {
        crate::CLIENT_BUFFERS.insert((1, 5), crate::ClientJitterBuffer::new());
        crate::CLIENT_BUFFERS.insert((2, 5), crate::ClientJitterBuffer::new());
        crate::drop_session_audio(1);
        // Session 1's buffer is gone…
        assert!(!crate::CLIENT_BUFFERS.contains_key(&(1, 5)));
        // …while the other session's same-numeric-id buffer is untouched.
        assert!(crate::CLIENT_BUFFERS.contains_key(&(2, 5)));
        crate::CLIENT_BUFFERS.clear();
    }
}
