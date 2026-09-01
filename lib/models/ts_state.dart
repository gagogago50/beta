import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_locale.dart';
import '../models/channel.dart';
import '../models/client.dart';
import '../models/contact_settings.dart';
import '../models/file_transfer.dart';
import '../models/server_file.dart';
import '../models/poll_policy.dart';
import '../models/reconnect_policy.dart';
import '../models/chat_message.dart';
import '../models/resume_intent.dart';
import '../models/server.dart';
import '../models/server_order.dart';
import '../services/ts_ffi.dart';
import '../services/app_log.dart';
import '../services/audio_route_service.dart';
import '../services/audio_service.dart';
import '../services/chat_history_service.dart';
import '../services/connectivity_service.dart';
import '../services/icon_cache.dart';
import '../services/foreground_service.dart';
import '../services/secure_storage.dart';

/// Log tag for everything connection/state related.
const _tag = 'ts';

// ─── Immutable State ────────────────────────────────────────────────

class TsConnectionState {
  /// Handle of the session this snapshot belongs to (0 = engine-wide/empty).
  final int connectionId;

  final bool connected;
  final bool connecting;
  final String serverName;

  /// Stable server identity (base64 of the public key hash). Scopes caches
  /// that must not leak between servers, like group icons.
  final String serverUid;
  final String voiceEncryptionMode;

  /// `virtualserver_welcomemessage`: shown to every new client on connect.
  final String welcomeMessage;

  /// `virtualserver_hostmessage`: a server-operator notice.
  final String hostMessage;

  /// `virtualserver_hostmessage_mode`: 0 = none, 1 = log (show in chat),
  /// 2 = modal, 3 = modal + disconnect.
  final int hostMessageMode;

  /// `virtualserver_maxclients`: capacity of the virtual server.
  final int maxClients;

  /// `virtualserver_needed_identity_security_level`: the identity level the
  /// server requires; a lower level is refused during the handshake.
  final int neededIdentitySecurityLevel;

  final String nickname;
  final int ownClientId;
  final List<TsChannel> channels;
  final List<TsClient> clients;
  final List<ChatMessage> messages;
  final int? selectedChannelId;
  final String? error;
  final String? errorCode;
  final String? missingPermission;
  final int rttMs;
  final int rttDeviationMs;

  /// Inter-arrival jitter computed by the engine from consecutive RTT samples.
  final int jitterMs;
  final double packetLossPercent;
  final List<String> diagMessages;

  /// Live file transfers (uploads and downloads) for this session.
  final List<FileTransfer> transfers;

  /// The channel file listing shown in the file browser. Empty when nothing
  /// has been requested yet. `serverFilePath` is the directory currently
  /// displayed; `serverFilesLoading` is true while a `ftgetfilelist` is in
  /// flight; `serverFilesError` carries a human-readable failure.
  final List<ServerFile> serverFiles;
  final String serverFilePath;
  final bool serverFilesLoading;
  final String? serverFilesError;
  final bool voiceActive;
  final bool inputMuted;
  final bool outputMuted;
  final bool pttMode;
  final bool pttPressed;
  final bool vadEnabled;
  final double vadThreshold;
  final double micGain;
  final double micRms;

  /// Whisper transmission is armed: voice frames leave as whisper packets
  /// addressed to [whisperTargetClientIds] / [whisperTargetChannelIds].
  final bool whisperActive;
  final List<int> whisperTargetClientIds;
  final List<int> whisperTargetChannelIds;

  /// Only play incoming whispers coming from [whisperAllowedUids].
  final bool whisperAllowlistEnabled;
  final List<String> whisperAllowedUids;

  /// Incoming whisper frames dropped by the allow list this session.
  final int whisperIgnoredCount;

  /// Explicit connection state machine phase.
  final TsPhase phase;

  /// Structured failure kind of the last connection attempt (`timeout`,
  /// `password`, `banned`, …) as classified by the Rust engine.
  final String? connectErrorKind;

  /// 1-based index of the automatic reconnection attempt in progress, 0 when
  /// no automatic reconnection is scheduled or running.
  final int reconnectAttempt;

  /// When the scheduled reconnection will fire, for the countdown in the UI.
  final DateTime? reconnectAt;

  /// User preference: retry transient drops automatically.
  final bool autoReconnectEnabled;

  /// Unread counters per conversation thread key.
  final Map<String, int> unreadByThread;

  /// Opt-in encrypted chat history and how long it is kept.
  final bool chatHistoryEnabled;
  final HistoryRetention chatRetention;

  /// Requested audio output route and the routes this device offers.
  final AudioRoute audioRoute;
  final List<AudioRoute> availableRoutes;

  /// Local user's away/AFK state and reason, as requested by the user (the
  /// server confirms it through the roster).
  final bool away;
  final String? awayMessage;
  final bool channelCommander;

  /// Outgoing commands queued by the anti-flood budget, and whether the
  /// engine is in degraded mode after the server complained.
  final int pendingCommands;
  final bool commandRateDegraded;

  /// Platform DSP effects: user preference and hardware availability.
  final bool aecEnabled;
  final bool nsEnabled;
  final bool agcEnabled;
  final AudioEffectSupport effectSupport;

  /// Channel ids the user pinned as favorites (per server). Pinned channels
  /// are shown first in the tree.
  final Set<int> favoriteChannelIds;

  /// When true the channel tree sorts alphabetically instead of by the
  /// server's `order` field.
  final bool channelsSortedAlpha;

  /// Play a sound when a message arrives in a conversation that is not on
  /// screen (opt-in; off by default to respect the user's environment).
  final bool eventSoundsEnabled;

  const TsConnectionState({
    this.connectionId = 0,
    this.connected = false,
    this.connecting = false,
    this.serverName = '',
    this.serverUid = '',
    this.voiceEncryptionMode = 'Unknown',
    this.welcomeMessage = '',
    this.hostMessage = '',
    this.hostMessageMode = 0,
    this.maxClients = 0,
    this.neededIdentitySecurityLevel = 0,
    this.nickname = '',
    this.ownClientId = 0,
    this.channels = const [],
    this.clients = const [],
    this.messages = const [],
    this.selectedChannelId,
    this.error,
    this.errorCode,
    this.missingPermission,
    this.rttMs = 0,
    this.rttDeviationMs = 0,
    this.jitterMs = 0,
    this.packetLossPercent = 0.0,
    this.diagMessages = const [],
    this.transfers = const [],
    this.serverFiles = const [],
    this.serverFilePath = '/',
    this.serverFilesLoading = false,
    this.serverFilesError,
    this.voiceActive = false,
    this.inputMuted = false,
    this.outputMuted = false,
    this.pttMode = false,
    this.pttPressed = false,
    this.vadEnabled = true,
    this.vadThreshold = 0.005,
    this.micGain = 1.0,
    this.micRms = 0.0,
    this.whisperActive = false,
    this.whisperTargetClientIds = const [],
    this.whisperTargetChannelIds = const [],
    this.whisperAllowlistEnabled = false,
    this.whisperAllowedUids = const [],
    this.whisperIgnoredCount = 0,
    this.phase = TsPhase.idle,
    this.connectErrorKind,
    this.reconnectAttempt = 0,
    this.reconnectAt,
    this.autoReconnectEnabled = true,
    this.unreadByThread = const {},
    this.chatHistoryEnabled = false,
    this.chatRetention = HistoryRetention.thirtyDays,
    this.audioRoute = AudioRoute.auto,
    this.availableRoutes = const [AudioRoute.auto],
    this.away = false,
    this.awayMessage,
    this.channelCommander = false,
    this.pendingCommands = 0,
    this.commandRateDegraded = false,
    this.aecEnabled = true,
    this.nsEnabled = true,
    this.agcEnabled = false,
    this.effectSupport = AudioEffectSupport.none,
    this.favoriteChannelIds = const {},
    this.channelsSortedAlpha = false,
    this.eventSoundsEnabled = false,
  });

  TsConnectionState copyWith({
    int? connectionId,
    bool? connected,
    bool? connecting,
    String? serverName,
    String? serverUid,
    String? voiceEncryptionMode,
    String? welcomeMessage,
    String? hostMessage,
    int? hostMessageMode,
    int? maxClients,
    int? neededIdentitySecurityLevel,
    String? nickname,
    int? ownClientId,
    List<TsChannel>? channels,
    List<TsClient>? clients,
    List<ChatMessage>? messages,
    Object? selectedChannelId = _sentinel,
    String? error,
    String? errorCode,
    String? missingPermission,
    int? rttMs,
    int? rttDeviationMs,
    int? jitterMs,
    double? packetLossPercent,
    List<String>? diagMessages,
    List<FileTransfer>? transfers,
    List<ServerFile>? serverFiles,
    String? serverFilePath,
    bool? serverFilesLoading,
    Object? serverFilesError = _sentinel,
    bool? voiceActive,
    bool? inputMuted,
    bool? outputMuted,
    bool? pttMode,
    bool? pttPressed,
    bool? vadEnabled,
    double? vadThreshold,
    double? micGain,
    double? micRms,
    bool? whisperActive,
    List<int>? whisperTargetClientIds,
    List<int>? whisperTargetChannelIds,
    bool? whisperAllowlistEnabled,
    List<String>? whisperAllowedUids,
    int? whisperIgnoredCount,
    TsPhase? phase,
    String? connectErrorKind,
    int? reconnectAttempt,
    Object? reconnectAt = _sentinel,
    bool? autoReconnectEnabled,
    Map<String, int>? unreadByThread,
    bool? chatHistoryEnabled,
    HistoryRetention? chatRetention,
    AudioRoute? audioRoute,
    List<AudioRoute>? availableRoutes,
    bool? away,
    // Sentinel: clearing the away flag must be able to erase the reason too,
    // which a plain nullable parameter cannot express.
    Object? awayMessage = _sentinel,
    bool? channelCommander,
    int? pendingCommands,
    bool? commandRateDegraded,
    bool? aecEnabled,
    bool? nsEnabled,
    bool? agcEnabled,
    AudioEffectSupport? effectSupport,
    Set<int>? favoriteChannelIds,
    bool? channelsSortedAlpha,
    bool? eventSoundsEnabled,
  }) => TsConnectionState(
    connectionId: connectionId ?? this.connectionId,
    connected: connected ?? this.connected,
    connecting: connecting ?? this.connecting,
    serverName: serverName ?? this.serverName,
    serverUid: serverUid ?? this.serverUid,
    voiceEncryptionMode: voiceEncryptionMode ?? this.voiceEncryptionMode,
    welcomeMessage: welcomeMessage ?? this.welcomeMessage,
    hostMessage: hostMessage ?? this.hostMessage,
    hostMessageMode: hostMessageMode ?? this.hostMessageMode,
    maxClients: maxClients ?? this.maxClients,
    neededIdentitySecurityLevel:
        neededIdentitySecurityLevel ?? this.neededIdentitySecurityLevel,
    nickname: nickname ?? this.nickname,
    ownClientId: ownClientId ?? this.ownClientId,
    channels: channels ?? this.channels,
    clients: clients ?? this.clients,
    messages: messages ?? this.messages,
    selectedChannelId: selectedChannelId == _sentinel
        ? this.selectedChannelId
        : selectedChannelId as int?,
    error: error,
    errorCode: errorCode,
    missingPermission: missingPermission,
    rttMs: rttMs ?? this.rttMs,
    rttDeviationMs: rttDeviationMs ?? this.rttDeviationMs,
    jitterMs: jitterMs ?? this.jitterMs,
    packetLossPercent: packetLossPercent ?? this.packetLossPercent,
    diagMessages: diagMessages ?? this.diagMessages,
    transfers: transfers ?? this.transfers,
    serverFiles: serverFiles ?? this.serverFiles,
    serverFilePath: serverFilePath ?? this.serverFilePath,
    serverFilesLoading: serverFilesLoading ?? this.serverFilesLoading,
    serverFilesError: serverFilesError == _sentinel
        ? this.serverFilesError
        : serverFilesError as String?,
    voiceActive: voiceActive ?? this.voiceActive,
    inputMuted: inputMuted ?? this.inputMuted,
    outputMuted: outputMuted ?? this.outputMuted,
    pttMode: pttMode ?? this.pttMode,
    pttPressed: pttPressed ?? this.pttPressed,
    vadEnabled: vadEnabled ?? this.vadEnabled,
    vadThreshold: vadThreshold ?? this.vadThreshold,
    micGain: micGain ?? this.micGain,
    micRms: micRms ?? this.micRms,
    whisperActive: whisperActive ?? this.whisperActive,
    whisperTargetClientIds:
        whisperTargetClientIds ?? this.whisperTargetClientIds,
    whisperTargetChannelIds:
        whisperTargetChannelIds ?? this.whisperTargetChannelIds,
    whisperAllowlistEnabled:
        whisperAllowlistEnabled ?? this.whisperAllowlistEnabled,
    whisperAllowedUids: whisperAllowedUids ?? this.whisperAllowedUids,
    whisperIgnoredCount: whisperIgnoredCount ?? this.whisperIgnoredCount,
    phase: phase ?? this.phase,
    // Same one-shot semantics as `error`: a state update that does not carry a
    // failure kind clears it, so a stale reason never sticks to a new attempt.
    connectErrorKind: connectErrorKind,
    reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
    reconnectAt: reconnectAt == _sentinel
        ? this.reconnectAt
        : reconnectAt as DateTime?,
    autoReconnectEnabled: autoReconnectEnabled ?? this.autoReconnectEnabled,
    unreadByThread: unreadByThread ?? this.unreadByThread,
    chatHistoryEnabled: chatHistoryEnabled ?? this.chatHistoryEnabled,
    chatRetention: chatRetention ?? this.chatRetention,
    audioRoute: audioRoute ?? this.audioRoute,
    availableRoutes: availableRoutes ?? this.availableRoutes,
    away: away ?? this.away,
    awayMessage: awayMessage == _sentinel
        ? this.awayMessage
        : awayMessage as String?,
    channelCommander: channelCommander ?? this.channelCommander,
    pendingCommands: pendingCommands ?? this.pendingCommands,
    commandRateDegraded: commandRateDegraded ?? this.commandRateDegraded,
    aecEnabled: aecEnabled ?? this.aecEnabled,
    nsEnabled: nsEnabled ?? this.nsEnabled,
    agcEnabled: agcEnabled ?? this.agcEnabled,
    effectSupport: effectSupport ?? this.effectSupport,
    favoriteChannelIds: favoriteChannelIds ?? this.favoriteChannelIds,
    channelsSortedAlpha: channelsSortedAlpha ?? this.channelsSortedAlpha,
    eventSoundsEnabled: eventSoundsEnabled ?? this.eventSoundsEnabled,
  );

  /// Conversations, most recently active private thread first.
  List<ChatThread> get threads =>
      ChatThread.group(messages, unreadByThread: unreadByThread);

  /// Total unread messages across every thread, for the collapsed chat bar.
  int get totalUnread =>
      unreadByThread.values.fold(0, (sum, count) => sum + count);

  /// Whisper can only be armed once at least one target is selected.
  bool get hasWhisperTargets =>
      whisperTargetClientIds.isNotEmpty || whisperTargetChannelIds.isNotEmpty;

  /// The channel the local user is currently in.
  TsChannel? get currentChannel {
    if (selectedChannelId == null) return null;
    return channels.where((c) => c.id == selectedChannelId).firstOrNull;
  }

  /// Whether the local user may speak in the currently selected channel.
  ///
  /// Mirrors the desktop client: you need at least the channel's required talk
  /// power (or an explicit server grant) to be heard. A channel with no talk
  /// power requirement always allows speech.
  bool get canTalkInCurrentChannel {
    final channel = currentChannel;
    if (channel == null || channel.neededTalkPower <= 0) return true;
    final self = clients.where((c) => c.id == ownClientId).firstOrNull;
    if (self == null) return false;
    return self.talkPowerGranted || self.talkPower >= channel.neededTalkPower;
  }
}

const _sentinel = Object();

// ─── Saved Servers State ────────────────────────────────────────────

class ServerListState {
  final List<Server> servers;

  /// Server ids the user pinned. Pinned servers sort first on the home screen.
  final Set<String> favoriteIds;
  final bool loading;

  const ServerListState({
    this.servers = const [],
    this.favoriteIds = const {},
    this.loading = true,
  });

  ServerListState copyWith({
    List<Server>? servers,
    Set<String>? favoriteIds,
    bool? loading,
  }) => ServerListState(
    servers: servers ?? this.servers,
    favoriteIds: favoriteIds ?? this.favoriteIds,
    loading: loading ?? this.loading,
  );
}

// ─── Multi-server coordination state ────────────────────────────────

/// Immutable snapshot of every live connection plus the tab ordering.
class MultiServerState {
  /// Per-session state, keyed by the connection id from the engine.
  final Map<int, TsConnectionState> sessions;

  /// Tab order (a connection id list). Kept separate from the map so the tab
  /// order survives a session that flickered to a disconnected state.
  final List<int> order;

  /// The connection id of the currently focused server tab.
  final int? selectedId;

  /// Human labels for the server tabs (address before connection, server
  /// name once the handshake succeeds).
  final Map<int, String> labels;

  const MultiServerState({
    this.sessions = const {},
    this.order = const [],
    this.selectedId,
    this.labels = const {},
  });

  TsConnectionState get selected =>
      sessions[selectedId] ?? const TsConnectionState();

  bool get hasAnyConnected => sessions.values.any((s) => s.connected);

  int get connectedCount => sessions.values.where((s) => s.connected).length;

  String labelFor(int cid) => labels[cid] ?? 'server';

  MultiServerState copyWith({
    Map<int, TsConnectionState>? sessions,
    List<int>? order,
    Object? selectedId = _sentinel,
    Map<int, String>? labels,
  }) => MultiServerState(
    sessions: sessions ?? this.sessions,
    order: order ?? this.order,
    selectedId: selectedId == _sentinel ? this.selectedId : selectedId as int?,
    labels: labels ?? this.labels,
  );
}

/// The per-session view handed to the UI: the state plus a facade of actions.
class TsSessionView {
  final TsConnectionState state;
  final TsConnectionNotifier actions;
  const TsSessionView({required this.state, required this.actions});
}

// ─── Per-session runtime bookkeeping ────────────────────────────────

/// Mutable, non-Riverpod state that the controller keeps per connection.
class _SessionRuntime {
  final int connectionId;
  String label;
  String address;
  String nickname;
  _ConnectRequest? lastRequest;
  Timer? reconnectTimer;
  String? channelToRestore;
  bool autoReconnect = true;
  Timer? historySaveTimer;
  bool mutedByFocusLoss = false;
  String? openThread;
  DateTime lastThrottleEvent = DateTime.fromMillisecondsSinceEpoch(0);

  _SessionRuntime({
    required this.connectionId,
    required this.address,
    required this.nickname,
    required this.label,
  });
}

// ─── Lifecycle / connectivity observers (shared, registered once) ──

class _LifecycleWatcher with WidgetsBindingObserver {
  _LifecycleWatcher(this.onChanged);
  final void Function(bool foreground) onChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onChanged(state == AppLifecycleState.resumed);
  }
}

// ─── Multi-server notifier (single poll loop + shared infrastructure) ─

class MultiServerNotifier extends Notifier<MultiServerState> {
  Timer? _pollTimer;
  bool _nativeWakeScheduled = false;
  DateTime _lastRosterRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  /// The request_id of the most recent `ftgetfilelist` this session issued,
  /// so a stale/other `file_list` reply does not clobber the visible panel.
  final Map<int, int> _lastFileRequestId = {};
  AudioService? _audioService;
  bool _micEnabled = false;
  bool _micGranted = false;
  SharedPreferences? _prefs;
  bool _foreground = true;
  _LifecycleWatcher? _lifecycle;
  StreamSubscription<NetworkStatus>? _networkSub;
  NetworkStatus _network = NetworkStatus.unknown;

  final Map<int, _SessionRuntime> _rt = {};

  // ─── Perf: throttle the highest-frequency state writes ─────────────
  // The mic-level callback fires ~50×/s and the notification is a platform
  // channel call; letting either hammer `state` (or the MethodChannel) was the
  // main source of UI jank and CPU/heat on a real phone. These bounds keep the
  // UI responsive and the cores cool without losing any visible signal.
  static const _micLevelThrottle = Duration(milliseconds: 100);
  static const _notifyThrottle = Duration(milliseconds: 600);
  static const _maxDiagMessages = 40;
  DateTime _lastMicLevelWrite = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastNotification = DateTime.fromMillisecondsSinceEpoch(0);

  /// Master output volume (dB) captured before an audio-focus duck, restored on
  /// the corresponding regain. Null = not currently ducked.
  double? _volumeBeforeDuck;

  /// How much to lower the output on a transient focus loss, in dB. The legacy
  /// client halves the stream volume (≈ −6 dB) whenever another app takes focus.
  static const _duckDbOffset = 6.0;

  @override
  MultiServerState build() {
    ForegroundService.init();
    TsNative.initializeEventNotifier();
    TsNative.onEventsAvailable = _onNativeEventsAvailable;
    ForegroundService.onToggleMute = (bool inputMuted) {
      final cid = state.selectedId;
      if (cid != null && state.sessions[cid]?.inputMuted != inputMuted) {
        toggleInputMute(cid);
      }
    };
    ForegroundService.onSetFullMute = setFullMuteAll;
    ForegroundService.onNotificationDisconnect = () {
      disconnectAll();
    };

    _networkSub = ConnectivityService.watch().listen(_onNetworkChanged);
    final lifecycle = _LifecycleWatcher(_onForegroundChanged);
    _lifecycle = lifecycle;
    WidgetsBinding.instance.addObserver(lifecycle);
    AudioRouteService.setFocusListeners(
      onLost: _onAudioFocusLost,
      onRegained: _onAudioFocusRegained,
    );

    ref.onDispose(() {
      _pollTimer?.cancel();
      _networkSub?.cancel();
      for (final rt in _rt.values) {
        rt.reconnectTimer?.cancel();
        rt.historySaveTimer?.cancel();
      }
      final lifecycle = _lifecycle;
      if (lifecycle != null) WidgetsBinding.instance.removeObserver(lifecycle);
      TsNative.onEventsAvailable = null;
      ForegroundService.onToggleMute = null;
      ForegroundService.onSetFullMute = null;
      ForegroundService.onNotificationDisconnect = null;
    });
    return const MultiServerState();
  }

  // ─── State mutation helpers ───────────────────────────────────────

  TsConnectionState _stateOf(int cid) =>
      state.sessions[cid] ?? TsConnectionState(connectionId: cid);

  void _setSession(int cid, TsConnectionState next) {
    final sessions = Map<int, TsConnectionState>.from(state.sessions)
      ..[cid] = next;
    final order = state.order.contains(cid)
        ? state.order
        : [...state.order, cid];
    state = state.copyWith(sessions: sessions, order: order);
  }

  void _setLabel(int cid, String label) {
    final labels = Map<int, String>.from(state.labels)..[cid] = label;
    state = state.copyWith(labels: labels);
    if (_rt[cid] != null) _rt[cid]!.label = label;
  }

  /// Builds the per-session facade the UI uses for actions.
  TsConnectionNotifier controllerFor(int cid) =>
      TsConnectionNotifier(this, cid);

  // ─── Connect ──────────────────────────────────────────────────────

  Future<void> connect({
    required String address,
    required String nickname,
    String? channel,
    String? password,
    String? channelPassword,
  }) async {
    AppLog.i(_tag, 'connect requested (server set: ${channel != null})');
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    _migrateLegacyVolumeKeys();
    String? id;
    try {
      id = await SecureStorage.get(SecureStorage.identityKey);
      final legacyId = prefs.getString('client_identity');
      if (id == null && legacyId != null) {
        await SecureStorage.put(SecureStorage.identityKey, legacyId);
        await prefs.remove('client_identity');
        id = legacyId;
        AppLog.i(_tag, 'legacy identity migrated to secure storage');
      }
    } catch (error) {
      AppLog.e(_tag, 'secure identity read failed', error);
      // Fail fast: without an identity the handshake may still work on servers
      // that allow guest connections, so surface the problem but continue.
    }
    if (id != null) {
      AppLog.d(_tag, 'pushing encrypted identity to the engine');
      TsNative.setIdentity(id);
    }
    final savedMicGain = prefs.getDouble('mic_gain');
    // Effects must be configured before the capture session starts.
    await loadAudioPreferences();
    IconCache.reset();
    await loadHistoryPreferences();
    unawaited(IconCache.purgeExpired());

    final resultJson = TsNative.connect(
      address,
      nickname,
      channel: channel,
      password: password,
      channelPassword: channelPassword,
    );
    final result = jsonDecode(resultJson) as Map<String, dynamic>;
    if (result['type'] == 'error') {
      AppLog.e(_tag, 'connect rejected by the engine: ${result['message']}');
      return;
    }
    final cid = (result['connection_id'] as num?)?.toInt();
    if (cid == null || cid == 0) {
      AppLog.e(_tag, 'connect did not return a connection id');
      return;
    }
    final initialLabel = _tabLabel(address, nickname);
    final rt = _SessionRuntime(
      connectionId: cid,
      address: address,
      nickname: nickname,
      label: initialLabel,
    );
    rt.lastRequest = _ConnectRequest(
      address: address,
      nickname: nickname,
      channel: channel,
      password: password,
      channelPassword: channelPassword,
    );
    _rt[cid] = rt;
    if (savedMicGain != null) setMicGain(cid, savedMicGain);
    _setLabel(cid, initialLabel);
    _setSession(
      cid,
      _stateOf(cid).copyWith(
        connecting: true,
        phase: TsPhase.resolving,
        reconnectAt: null,
        error: null,
      ),
    );
    // Preserve the identity in secure storage after a successful handshake.
    _saveIdentity();
    // Auto-focus the new tab.
    state = state.copyWith(selectedId: cid);
    _startPolling();
  }

  /// Handle of the session the microphone currently transmits to.
  int get _micConnectionId => state.selectedId ?? _rt.keys.firstOrNull ?? 0;

  void _saveIdentity() async {
    final id = TsNative.getIdentity();
    if (id == null) return;
    try {
      await SecureStorage.put(SecureStorage.identityKey, id);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('client_identity');
      AppLog.i(_tag, 'identity saved to Keystore-backed storage');
    } catch (error) {
      AppLog.e(_tag, 'secure identity write failed', error);
    }
  }

  void _onNativeEventsAvailable() {
    if (_nativeWakeScheduled || state.sessions.isEmpty) return;
    _nativeWakeScheduled = true;
    scheduleMicrotask(() {
      _nativeWakeScheduled = false;
      if (state.sessions.isEmpty) return;
      _pollTimer?.cancel();
      _pollEvents();
    });
  }

  void _startPolling() {
    AppLog.d(_tag, 'native event notifications enabled with safety polling');
    if (state.sessions.isEmpty) return;
    _pollTimer?.cancel();
    _scheduleNextPoll(Duration.zero);
  }

  void _scheduleNextPoll([Duration? delay]) {
    if (state.sessions.isEmpty) return;
    final connected = state.hasAnyConnected;
    final capturing =
        _micEnabled || state.sessions.values.any((s) => s.voiceActive);
    final interval =
        delay ??
        PollPolicy.intervalFor(
          connected: connected,
          capturing: capturing,
          foreground: _foreground,
        );
    _pollTimer = Timer(interval, _pollEvents);
  }

  void _pollEvents() {
    try {
      final events = TsNative.pollEvents();
      for (final event in events) {
        _handleEvent(event);
      }
      // Voice activity indicator for the currently-visible (or mic) session.
      final micCid = _micConnectionId;
      if (micCid != 0 && _rt.containsKey(micCid)) {
        final va = TsNative.isVoiceActive(micCid);
        if (va != _stateOf(micCid).voiceActive) {
          _setSession(micCid, _stateOf(micCid).copyWith(voiceActive: va));
          _refreshNotification();
        }
      }
      final now = DateTime.now();
      if (PollPolicy.shouldReconcileRoster(foreground: _foreground) &&
          now.difference(_lastRosterRefresh) >= const Duration(seconds: 2)) {
        _lastRosterRefresh = now;
        for (final cid in state.sessions.keys) {
          try {
            final clientsJson = TsNative.getClients(cid);
            final clients = (jsonDecode(clientsJson) as List)
                .map((j) => TsClient.fromJson(j as Map<String, dynamic>))
                .toList();
            // Only write to state when the roster actually changed: writing an
            // identical list every 2s rebuilds the whole client list for
            // nothing, which is a major source of jank on a real phone.
            if (clients.isNotEmpty &&
                !listEquals(clients, _stateOf(cid).clients)) {
              _setSession(cid, _stateOf(cid).copyWith(clients: clients));
            }
            _applySavedClientVolumes(cid);
            _pruneWhisperTargets(cid);
            final rt = _rt[cid];
            final s = _stateOf(cid);
            if (s.pendingCommands > 0 &&
                DateTime.now().difference(rt?.lastThrottleEvent ?? now) >
                    const Duration(seconds: 3)) {
              _setSession(cid, s.copyWith(pendingCommands: 0));
            }
            _refreshWhisperStats(cid);
          } catch (error) {
            AppLog.e(
              _tag,
              'roster reconciliation failed (session $cid)',
              error,
            );
          }
        }
      }
    } catch (error) {
      AppLog.e(_tag, 'FFI poll error', error);
    } finally {
      _scheduleNextPoll();
    }
  }

  void _handleEvent(TsEngineEvent event) {
    final cid = event.connectionId;
    final data = event.data;
    AppLog.d(_tag, 'event ${event.type} (session $cid)');
    if (cid != 0 && !_rt.containsKey(cid)) {
      // A late event for an already-removed session: ignore.
      AppLog.d(_tag, 'dropped event for unknown session $cid');
      return;
    }
    switch (event.type) {
      case 'connected':
        final channelsJson = TsNative.getChannels(cid);
        final clientsJson = TsNative.getClients(cid);
        final channels = (jsonDecode(channelsJson) as List)
            .map((j) => TsChannel.fromJson(j as Map<String, dynamic>))
            .toList();
        final clients = (jsonDecode(clientsJson) as List)
            .map((j) => TsClient.fromJson(j as Map<String, dynamic>))
            .toList();
        final ownId = data['client_id'] as int? ?? _stateOf(cid).ownClientId;
        final ownClient = clients.where((c) => c.id == ownId).firstOrNull;
        final joinedChannelId = ownClient?.channelId;
        final st = _stateOf(cid).copyWith(
          connecting: false,
          connected: true,
          serverName: data['server_name'] as String? ?? '',
          serverUid: data['server_uid'] as String? ?? '',
          voiceEncryptionMode:
              data['voice_encryption_mode'] as String? ?? 'Unknown',
          welcomeMessage: data['welcome_message'] as String? ?? '',
          hostMessage: data['host_message'] as String? ?? '',
          hostMessageMode: data['host_message_mode'] as int? ?? 0,
          maxClients: data['max_clients'] as int? ?? 0,
          neededIdentitySecurityLevel:
              data['needed_identity_security_level'] as int? ?? 0,
          ownClientId: ownId,
          channels: channels,
          clients: clients,
          selectedChannelId: joinedChannelId,
          phase: TsPhase.connected,
          reconnectAttempt: 0,
          reconnectAt: null,
        );
        _setSession(cid, st);
        _maybeHydrateServerMessages(cid, st);
        if (st.serverName.isNotEmpty) {
          _setLabel(cid, st.serverName);
        }
        _rt[cid]?.reconnectTimer?.cancel();
        unawaited(_restoreHistory(cid));
        unawaited(loadChannelUiPrefs(cid));
        _restoreChannelAfterReconnect(cid, channels);
        // C5: remember the last successful join so an app kill can offer a
        // resume. The mute flag is captured so a restart never re-opens the mic
        // on its own.
        unawaited(
          ResumeIntentStore.save(
            ResumeIntent(
              address: _rt[cid]?.address ?? '',
              nickname: _rt[cid]?.nickname ?? st.nickname,
              channel: _rt[cid]?.channelToRestore,
              micWasMuted: st.inputMuted,
            ),
          ),
        );
        if (_audioService == null) {
          _startAudioService();
        }
        _refreshNotification();
        break;

      case 'file_transfer':
        final tfId = data['transfer_id'] as int? ?? 0;
        IconCache.onTransferEvent(
          transferId: tfId,
          ok: data['ok'] as bool? ?? false,
          localPath: data['local_path'] as String? ?? '',
        );
        // Remove the transfer from the live list (completed or failed).
        final transfers = _stateOf(
          cid,
        ).transfers.where((t) => t.transferId != tfId).toList();
        _setSession(cid, _stateOf(cid).copyWith(transfers: transfers));
        if (data['ok'] != true) {
          AppLog.d(_tag, 'file transfer failed: ${data['error']}');
        }
        break;

      case 'file_transfer_progress':
        final tfId = data['transfer_id'] as int? ?? 0;
        final bytes = data['bytes'] as int? ?? 0;
        final total = data['total_bytes'] as int? ?? 0;
        final remote = data['remote_path'] as String? ?? '';
        _upsertTransfer(
          cid,
          FileTransfer(
            transferId: tfId,
            remotePath: remote,
            bytes: bytes,
            totalBytes: total,
            direction: FileTransferDirection.upload,
          ),
        );
        break;

      case 'file_list':
        final requestId = data['request_id'] as int? ?? 0;
        final ok = data['ok'] as bool? ?? false;
        final error = data['error'] as String?;
        final path = data['path'] as String? ?? '/';
        final files = (data['files'] as List<dynamic>? ?? const [])
            .map((f) => ServerFile.fromJson(f as Map<String, dynamic>))
            .toList();
        // Only accept a result if the request_id matches the most recent one
        // this session asked for (the engine produces one event per finished
        // request; a stale/other request is a no-op for the visible panel).
        if (requestId != 0 && requestId != _lastFileRequestId[cid]) {
          AppLog.d(_tag, 'ignored stale file_list (request $requestId)');
          break;
        }
        _setSession(
          cid,
          _stateOf(cid).copyWith(
            serverFiles: files,
            serverFilePath: path,
            serverFilesLoading: false,
            serverFilesError: ok ? null : (error ?? 'File listing failed'),
          ),
        );
        break;

      case 'command_throttled':
        final rt = _rt[cid];
        if (rt != null) {
          rt.lastThrottleEvent = DateTime.now();
        }
        _setSession(
          cid,
          _stateOf(cid).copyWith(
            pendingCommands: data['pending'] as int? ?? 0,
            commandRateDegraded: data['degraded'] as bool? ?? false,
          ),
        );
        break;

      case 'connection_phase':
        final phase = TsPhase.fromNative(data['phase'] as String? ?? '');
        if (_stateOf(cid).connected) break;
        _setSession(cid, _stateOf(cid).copyWith(phase: phase));
        break;

      case 'connect_failed':
        final kind = data['kind'] as String? ?? 'unknown';
        final detail = data['message'] as String? ?? kind;
        final message = _connectErrorMessage(kind, detail);
        final retryable = data['retryable'] as bool? ?? false;
        _pollTimer?.cancel();
        _setSession(
          cid,
          _stateOf(cid).copyWith(
            connecting: false,
            connected: false,
            error: message,
            connectErrorKind: kind,
            phase: TsPhase.failed,
          ),
        );
        _maybeScheduleReconnect(cid, kind: kind, retryable: retryable);
        break;

      case 'disconnected':
        if (_stateOf(cid).connecting) break; // stale event, ignore
        final expected = data['expected'] as bool? ?? true;
        final reason = data['reason'] as String? ?? '';
        _audioService?.stop();
        _audioService = null;
        _micEnabled = false;
        _micGranted = false;
        _pollTimer?.cancel();
        final rt = _rt[cid];
        if (rt != null) {
          rt.channelToRestore = _currentChannelName(cid);
          rt.reconnectTimer?.cancel();
          final st = _stateOf(cid);
          if (st.chatHistoryEnabled && st.serverUid.isNotEmpty) {
            unawaited(
              ChatHistoryService.save(
                st.serverUid,
                st.messages,
                retention: st.chatRetention,
              ),
            );
          }
          final keepHistory = st.chatHistoryEnabled;
          final retention = st.chatRetention;
          _setSession(
            cid,
            TsConnectionState(
              connectionId: cid,
              chatHistoryEnabled: keepHistory,
              chatRetention: retention,
            ),
          );
          if (!expected) {
            _setSession(
              cid,
              _stateOf(cid).copyWith(
                error: reason,
                connectErrorKind: 'connection_lost',
                phase: TsPhase.failed,
              ),
            );
            _maybeScheduleReconnect(
              cid,
              kind: 'connection_lost',
              retryable: true,
            );
          }
        }
        _refreshNotification();
        break;

      case 'error':
        final message = data['message'] as String;
        if (_stateOf(cid).connecting) {
          _setSession(
            cid,
            _stateOf(cid).copyWith(
              connecting: false,
              error: message,
              phase: TsPhase.failed,
            ),
          );
          _pollTimer?.cancel();
        } else {
          _setSession(cid, _stateOf(cid).copyWith(error: message));
        }
        break;

      case 'command_error':
        final code = data['code'] as String? ?? 'Unknown';
        final message = data['message'] as String? ?? code;
        final missingPermission = data['missing_permission'] as String?;
        _setSession(
          cid,
          _stateOf(cid).copyWith(
            error: _formatCommandError(code, message, missingPermission),
            errorCode: code,
            missingPermission: missingPermission,
          ),
        );
        break;

      case 'network_stats':
        _setSession(
          cid,
          _stateOf(cid).copyWith(
            rttMs: data['rtt_ms'] as int? ?? 0,
            rttDeviationMs: data['rtt_deviation_ms'] as int? ?? 0,
            jitterMs: data['jitter_ms'] as int? ?? 0,
            packetLossPercent:
                (data['packet_loss_percent'] as num?)?.toDouble() ?? 0.0,
          ),
        );
        break;

      case 'text_message':
        final fromId = data['from_client_id'] as int;
        final targetMode = data['target_mode'] as int;
        final fromName = data['from_client'] as String;
        final st = _stateOf(cid);
        final text = data['message'] as String;
        // Honor the contact book's ignore flags before storing anything: the
        // legacy client filters at the service level, before a message reaches
        // a thread. Private messages honour ignorePrivateChat; channel/server
        // (public) messages honour ignorePublicChat. Unknown clients fail open.
        final contact = _contactForClient(cid, fromId);
        if (contact != null) {
          final isPrivate = targetMode == 1;
          final isPublic = targetMode == 2 || targetMode == 3;
          if ((isPrivate && contact.ignorePrivateChat) ||
              (isPublic && contact.ignorePublicChat)) {
            AppLog.d(
              _tag,
              'dropped ${targetMode == 1 ? 'private' : 'public'} message '
              'from contact (ignored)',
            );
            break;
          }
        }
        // Highlight a message that mentions our own nickname, like the Windows
        // client. Empty text (a server-generated line) is marked as such.
        final flagged =
            text.isNotEmpty &&
            st.nickname.isNotEmpty &&
            text.toLowerCase().contains(st.nickname.toLowerCase());
        final msg = ChatMessage(
          id: st.messages.length,
          fromClient: fromName,
          fromClientId: fromId,
          targetMode: targetMode,
          message: text,
          timestamp: DateTime.now(),
          peerId: targetMode == 1 ? fromId : null,
          peerName: targetMode == 1 ? fromName : null,
          serverGenerated: text.isEmpty,
          highlighted: flagged,
        );
        _setSession(cid, st.copyWith(messages: [...st.messages, msg]));
        if (fromId != st.ownClientId) {
          _markUnread(cid, msg.threadKey);
          _maybePlayEventSound(cid, msg.threadKey);
        }
        _scheduleHistorySave(cid);
        break;

      case 'client_joined':
        final client = TsClient(
          id: data['client_id'] as int,
          nickname: data['nickname'] as String,
          channelId: data['channel_id'] as int,
        );
        _setSession(
          cid,
          _stateOf(cid).copyWith(clients: [..._stateOf(cid).clients, client]),
        );
        break;

      case 'client_left':
        final leftId = data['client_id'] as int;
        _setSession(
          cid,
          _stateOf(cid).copyWith(
            clients: _stateOf(
              cid,
            ).clients.where((c) => c.id != leftId).toList(),
          ),
        );
        break;

      case 'channels_updated':
        final st = _stateOf(cid);
        final newChannels = (jsonDecode(TsNative.getChannels(cid)) as List)
            .map((j) => TsChannel.fromJson(j as Map<String, dynamic>))
            .toList();
        final newClients = (jsonDecode(TsNative.getClients(cid)) as List)
            .map((j) => TsClient.fromJson(j as Map<String, dynamic>))
            .toList();
        // Skip the write when nothing changed (the server sends "updated" for
        // bookkeeping too); otherwise the tree/client list rebuilds needlessly.
        if (!listEquals(newChannels, st.channels) ||
            !listEquals(newClients, st.clients)) {
          _setSession(
            cid,
            st.copyWith(channels: newChannels, clients: newClients),
          );
        }
        break;

      case 'diag':
        AppLog.d('engine', data['msg'] as String);
        // Bound the list: an unbounded grow would rebuild on every engine
        // diagnostic (it is appended to the state on each one).
        final diag = [..._stateOf(cid).diagMessages, data['msg'] as String];
        if (diag.length > _maxDiagMessages) {
          diag.removeRange(0, diag.length - _maxDiagMessages);
        }
        _setSession(cid, _stateOf(cid).copyWith(diagMessages: diag));
        break;
    }
  }

  /// Surfaces the server's welcome message and host message (per its mode)
  /// into the server conversation, the way the desktop client does.
  ///
  /// - Welcome: a plain system line in the server thread.
  /// - Host message mode 1 (log): shown in the server thread.
  /// - Mode 2 (modal) / 3 (modal + disconnect): surfaced as a prominent
  ///   notice; mode 3 disconnects (the server asked us to leave).
  void _maybeHydrateServerMessages(int cid, TsConnectionState st) {
    final messages = [...st.messages];
    final serverAppend = <ChatMessage>[];

    void pushSystem(String text) {
      serverAppend.add(
        ChatMessage(
          id: messages.length + serverAppend.length,
          fromClient: '',
          fromClientId: 0,
          targetMode: 3,
          message: text,
          timestamp: DateTime.now(),
          serverGenerated: true,
          highlighted: true,
        ),
      );
    }

    if (st.welcomeMessage.isNotEmpty) {
      pushSystem(st.welcomeMessage);
    }

    // Host message: only surface it if the server configured one and its mode
    // tells us to show it (mode 0 = hide).
    if (st.hostMessage.isNotEmpty && st.hostMessageMode == 1) {
      pushSystem(st.hostMessage);
    }

    if (serverAppend.isNotEmpty) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(messages: [...messages, ...serverAppend]),
      );
    }

    if (st.hostMessage.isNotEmpty && st.hostMessageMode >= 2) {
      // Mode 2 (modal) and 3 (modal + disconnect) are treated as a blocking
      // server notice; mode 3 additionally means the server wants us gone.
      final notice = st.hostMessageMode == 3
          ? '${st.hostMessage}\n(The server requested this connection to close.)'
          : st.hostMessage;
      _setSession(
        cid,
        _stateOf(cid).copyWith(hostMessage: notice, error: notice),
      );
      if (st.hostMessageMode == 3) {
        AppLog.i(_tag, 'host message mode 3, disconnecting');
        disconnect(cid);
      }
    }
  }

  String _formatCommandError(
    String code,
    String message,
    String? missingPermission,
  ) {
    if (code.contains('InvalidPassword')) {
      return 'The server or channel password was rejected';
    }
    if (code.contains('Insufficient') || missingPermission != null) {
      return missingPermission == null
          ? 'The server denied this operation'
          : 'Missing TeamSpeak permission: $missingPermission';
    }
    if (code.contains('Flood')) {
      return 'The server rate limit was reached; retry later';
    }
    if (code.contains('ChannelNotFound')) {
      return 'The selected channel no longer exists';
    }
    return message.isEmpty ? code : message;
  }

  // ─── Disconnect ───────────────────────────────────────────────────

  void selectSession(int cid) {
    if (state.order.contains(cid)) {
      state = state.copyWith(selectedId: cid);
    }
  }

  /// The address of a session, for bookmarking the current server.
  String runtimeAddress(int cid) => _rt[cid]?.address ?? '';

  /// The channel the user is currently in (by name), for bookmarking.
  String? runtimeChannel(int cid) {
    final name = _currentChannelName(cid);
    return name.isEmpty ? null : name;
  }

  /// Forces an immediate roster re-read for a session (e.g. a "refresh"
  /// action) by clearing the reconcile watermark so the next poll re-fetches.
  void refreshRoster(int cid) {
    if (!_rt.containsKey(cid)) return;
    _lastRosterRefresh = DateTime.fromMillisecondsSinceEpoch(0);
    _startPolling();
  }

  void closeSession(int cid) {
    if (!_rt.containsKey(cid)) return;
    _rt[cid]?.reconnectTimer?.cancel();
    disconnect(cid);
  }

  void disconnect(int cid) {
    AppLog.i(_tag, 'disconnect requested (session $cid)');
    _rt[cid]?.reconnectTimer?.cancel();
    _rt[cid]?.channelToRestore = null;
    _setSession(
      cid,
      _stateOf(cid).copyWith(reconnectAttempt: 0, reconnectAt: null),
    );
    final st = _stateOf(cid);
    if (!st.connected && !st.connecting) return;
    if (_micConnectionId == cid) {
      _audioService?.stop();
      _audioService = null;
      _micEnabled = false;
      _micGranted = false;
    }
    _pollTimer?.cancel();
    TsNative.disconnect(cid);
    _setSession(cid, _stateOf(cid).copyWith(connecting: false));
    // A manual disconnect ends the session for good: forget the resume intent
    // for this session so the app does not offer a stale "resume" on next launch.
    if (_rt.keys.every((c) => !_stateOf(c).connected)) {
      unawaited(ResumeIntentStore.clear());
    }
    _startPolling();
    _refreshNotification();
  }

  /// Rejoins a previously saved session (C5). Never opens the mic on its own:
  /// the mic starts muted unless the user had it unmuted before the process
  /// died, and even then the first connect leaves it as-is until they act.
  Future<bool> resume(ResumeIntent intent) async {
    if (!intent.hasCredentials) return false;
    await connect(
      address: intent.address,
      nickname: intent.nickname,
      channel: intent.channel,
      // Passwords are re-read from Keystore per server; we only rejoin.
    );
    // The engine starts a fresh session with an idle mic; apply the saved mute
    // after the handshake lands (connect() may still be in flight).
    if (intent.micWasMuted) {
      // If a session was created, set input mute on connect.
      state = state.copyWith(
        sessions: {
          for (final e in state.sessions.entries)
            e.key: e.value.copyWith(inputMuted: true),
        },
      );
    }
    return true;
  }

  /// Swipe-away / "disconnect all": used by the notification action.
  void disconnectAll() {
    for (final cid in state.order.toList()) {
      disconnect(cid);
    }
  }

  // ─── Per-session actions ──────────────────────────────────────────

  void sendChannelMessage(int cid, String text) {
    final st = _stateOf(cid);
    if (!st.connected || text.isEmpty) return;
    TsNative.sendChannelMessage(cid, st.selectedChannelId ?? 0, text);
  }

  void sendServerMessage(int cid, String text) {
    final st = _stateOf(cid);
    if (!st.connected || text.trim().isEmpty) return;
    if (!TsNative.sendServerMessage(cid, text.trim())) {
      _setSession(
        cid,
        st.copyWith(error: 'Unable to queue the server message'),
      );
    }
  }

  void sendPrivateMessage(int cid, int clientId, String text) {
    final st = _stateOf(cid);
    if (!st.connected || text.isEmpty) return;
    if (!TsNative.sendPrivateMessage(cid, clientId, text)) {
      _setSession(
        cid,
        st.copyWith(error: 'Unable to queue the private message'),
      );
      return;
    }
    final peer = st.clients.where((c) => c.id == clientId).firstOrNull;
    final msg = ChatMessage(
      id: st.messages.length,
      fromClient: st.nickname,
      fromClientId: st.ownClientId,
      targetMode: 1,
      message: text,
      timestamp: DateTime.now(),
      peerId: clientId,
      peerName: peer?.nickname,
    );
    _setSession(cid, st.copyWith(messages: [...st.messages, msg]));
  }

  bool selectChannel(int cid, int channelId, {String? password}) {
    if (!TsNative.moveToChannel(cid, channelId, password: password)) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(error: 'Unable to queue the channel move'),
      );
      return false;
    }
    return true;
  }

  String _currentChannelName(int cid) {
    final st = _stateOf(cid);
    final own = st.clients.where((c) => c.id == st.ownClientId).firstOrNull;
    if (own == null) return '';
    return st.channels.where((c) => c.id == own.channelId).firstOrNull?.name ??
        '';
  }

  void _toggleInputMute(int cid) {
    final st = _stateOf(cid);
    final newMuted = !st.inputMuted;
    if (!newMuted) _rt[cid]?.mutedByFocusLoss = false;
    TsNative.setMuted(
      connectionId: cid,
      input: newMuted,
      output: st.outputMuted,
    );
    _setSession(cid, st.copyWith(inputMuted: newMuted));
    _updateMicState();
    _refreshNotification();
  }

  void toggleInputMute(int cid) => _toggleInputMute(cid);

  void setFullMute(int cid, bool muted) {
    final st = _stateOf(cid);
    if (st.inputMuted == muted && st.outputMuted == muted) return;
    TsNative.setMuted(connectionId: cid, input: muted, output: muted);
    _setSession(cid, st.copyWith(inputMuted: muted, outputMuted: muted));
    _updateMicState();
    _refreshNotification();
  }

  /// Full-mute every connected server (media card / notification action).
  void setFullMuteAll(bool muted) {
    for (final cid in state.order.toList()) {
      if (_stateOf(cid).connected) setFullMute(cid, muted);
    }
  }

  void toggleFullMute(int cid) {
    final st = _stateOf(cid);
    setFullMute(cid, !(st.inputMuted && st.outputMuted));
  }

  void toggleOutputMute(int cid) {
    final st = _stateOf(cid);
    final newMuted = !st.outputMuted;
    TsNative.setMuted(
      connectionId: cid,
      input: st.inputMuted,
      output: newMuted,
    );
    _setSession(cid, st.copyWith(outputMuted: newMuted));
    _refreshNotification();
  }

  void togglePttMode(int cid) {
    final st = _stateOf(cid);
    final newPtt = !st.pttMode;
    TsNative.setVadEnabled(cid, !newPtt);
    if (!newPtt) TsNative.setVadThreshold(cid, st.vadThreshold);
    _setSession(cid, st.copyWith(pttMode: newPtt));
    _updateMicState();
  }

  void setPttPressed(int cid, bool pressed) {
    _setSession(cid, _stateOf(cid).copyWith(pttPressed: pressed));
    _updateMicState();
  }

  void setVadThreshold(int cid, double threshold) {
    TsNative.setVadThreshold(cid, threshold);
    _setSession(cid, _stateOf(cid).copyWith(vadThreshold: threshold));
  }

  void setVadEnabled(int cid, bool enabled) {
    TsNative.setVadEnabled(cid, enabled);
    _setSession(cid, _stateOf(cid).copyWith(vadEnabled: enabled));
  }

  void setMicGain(int cid, double gain) {
    TsNative.setMicGain(cid, gain);
    _prefs?.setDouble('mic_gain', gain);
    _setSession(cid, _stateOf(cid).copyWith(micGain: gain));
  }

  void setClientVolume(int cid, int clientId, double volumeDb) {
    TsNative.setClientVolume(cid, clientId, volumeDb);
    final newClients = _stateOf(cid).clients.map((c) {
      if (c.id == clientId) return c.copyWith(volume: volumeDb);
      return c;
    }).toList();
    _setSession(cid, _stateOf(cid).copyWith(clients: newClients));
    final client = newClients.where((c) => c.id == clientId).firstOrNull;
    final uid = client?.uid;
    if (uid != null && uid.isNotEmpty) {
      _prefs?.setDouble('client_volume_uid_$uid', volumeDb);
    }
  }

  // ─── Moderation ───────────────────────────────────────────────────

  void kickClient(
    int cid,
    int clientId, {
    required bool fromServer,
    String? reason,
  }) {
    if (!_stateOf(cid).connected) return;
    if (!TsNative.kickClient(
      cid,
      clientId,
      fromServer: fromServer,
      reason: reason,
    )) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(error: 'Unable to queue the kick'),
      );
    }
  }

  void banClient(int cid, int clientId, {int seconds = 0, String? reason}) {
    if (!_stateOf(cid).connected) return;
    if (!TsNative.banClient(cid, clientId, seconds: seconds, reason: reason)) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(error: 'Unable to queue the ban'),
      );
    }
  }

  void pokeClient(int cid, int clientId, String message) {
    if (!_stateOf(cid).connected || message.trim().isEmpty) return;
    if (!TsNative.pokeClient(cid, clientId, message.trim())) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(error: 'Unable to queue the poke'),
      );
    }
  }

  void moveClient(int cid, int clientId, int channelId, {String? password}) {
    if (!_stateOf(cid).connected) return;
    if (!TsNative.moveClient(cid, clientId, channelId, password: password)) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(error: 'Unable to queue the move'),
      );
    }
  }

  // ─── Own status ───────────────────────────────────────────────────

  void setAway(int cid, bool away, {String? message}) {
    if (!_stateOf(cid).connected) return;
    if (!TsNative.setAway(cid, away, message: message)) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(error: 'Unable to queue the status change'),
      );
      return;
    }
    _setSession(
      cid,
      _stateOf(cid).copyWith(away: away, awayMessage: away ? message : null),
    );
  }

  bool setNickname(int cid, String nickname) {
    final st = _stateOf(cid);
    if (!st.connected) return false;
    final trimmed = nickname.trim();
    if (!TsNative.setNickname(cid, trimmed)) {
      _setSession(
        cid,
        st.copyWith(error: 'Nickname must be 3 to 30 characters'),
      );
      return false;
    }
    _setSession(cid, st.copyWith(nickname: trimmed));
    return true;
  }

  void setChannelCommander(int cid, bool enabled) {
    if (!_stateOf(cid).connected) return;
    if (!TsNative.setChannelCommander(cid, enabled)) return;
    _setSession(cid, _stateOf(cid).copyWith(channelCommander: enabled));
  }

  // ─── Audio focus (global) ─────────────────────────────────────────

  /// Duck the output when another app (a call, another voice client) takes
  /// audio focus. Mirrors the legacy `AudioSessionController.duck()`: capture
  /// is stopped and the playback level is halved (≈ −6 dB), then restored on
  /// `_onAudioFocusRegained`. The duck is deliberately not persisted.
  void _duckMasterVolume() {
    if (_volumeBeforeDuck != null) return; // already ducked
    final current = ref.read(masterVolumeProvider).volumeDb;
    _volumeBeforeDuck = current;
    ref
        .read(masterVolumeProvider.notifier)
        .setVolumeLive((current - _duckDbOffset).clamp(-20.0, 20.0));
    AppLog.d(
      _tag,
      'audio focus lost, ducking output ${current}dB → '
      '${(current - _duckDbOffset).clamp(-20.0, 20.0)}dB',
    );
  }

  /// Restore the ducked output level after focus is regained.
  void _unduckMasterVolume() {
    final saved = _volumeBeforeDuck;
    if (saved == null) return;
    _volumeBeforeDuck = null;
    ref.read(masterVolumeProvider.notifier).setVolumeLive(saved);
    AppLog.d(_tag, 'audio focus regained, unducking output to ${saved}dB');
  }

  void _onAudioFocusLost() {
    _duckMasterVolume();
    final cid = state.selectedId;
    if (cid != null && _stateOf(cid).connected && !_stateOf(cid).inputMuted) {
      AppLog.i(_tag, 'audio focus lost, muting the microphone');
      _rt[cid]?.mutedByFocusLoss = true;
      _toggleInputMute(cid);
    }
  }

  void _onAudioFocusRegained() {
    _unduckMasterVolume();
    final cid = state.selectedId;
    if (cid == null) return;
    if (!(_rt[cid]?.mutedByFocusLoss ?? false)) return;
    _rt[cid]?.mutedByFocusLoss = false;
    if (!_stateOf(cid).connected || !_stateOf(cid).inputMuted) return;
    AppLog.i(_tag, 'audio focus regained, restoring the microphone');
    _toggleInputMute(cid);
  }

  // ─── Connectivity-driven reconnection (global) ────────────────────

  void _onNetworkChanged(NetworkStatus status) {
    final previous = _network;
    _network = status;
    AppLog.d(_tag, 'network changed: $status');

    // A Wi-Fi ↔ mobile handover changes the local address for every server.
    if (status.isHandoverFrom(previous) && state.hasAnyConnected) {
      AppLog.i(_tag, 'network handover while connected, forcing a reconnect');
      for (final cid in state.order.toList()) {
        final rt = _rt[cid];
        if (rt != null && _stateOf(cid).connected) {
          rt.channelToRestore = _currentChannelName(cid);
          TsNative.disconnect(cid);
        }
      }
      return;
    }

    if (!status.available) {
      // Offline: stop the countdowns. Retrying without a network would consume
      // the attempt budget for nothing.
      for (final cid in _rt.keys) {
        final rt = _rt[cid];
        if (rt != null && _stateOf(cid).reconnectAt != null) {
          rt.reconnectTimer?.cancel();
          _setSession(cid, _stateOf(cid).copyWith(reconnectAt: null));
        }
      }
      return;
    }

    if (!previous.available) {
      for (final cid in _rt.keys) {
        if (_stateOf(cid).phase == TsPhase.reconnecting) retryNow(cid);
      }
    }
  }

  // ─── Conversation threads ─────────────────────────────────────────

  void _markUnread(int cid, ChatThreadKey key) {
    if (_rt[cid]?.openThread == key.value) return;
    final counters = Map<String, int>.from(_stateOf(cid).unreadByThread);
    counters[key.value] = (counters[key.value] ?? 0) + 1;
    _setSession(cid, _stateOf(cid).copyWith(unreadByThread: counters));
  }

  void openThread(int cid, ChatThreadKey key) {
    _rt[cid]?.openThread = key.value;
    final counters = Map<String, int>.from(_stateOf(cid).unreadByThread);
    if ((counters[key.value] ?? 0) == 0) return;
    counters.remove(key.value);
    _setSession(cid, _stateOf(cid).copyWith(unreadByThread: counters));
  }

  void closeThreads(int cid) => _rt[cid]?.openThread = null;

  ChatThreadKey openPrivateThread(int cid, int clientId) {
    final key = ChatThreadKey.privateWith(clientId);
    openThread(cid, key);
    return key;
  }

  // ─── Foreground / background (global) ─────────────────────────────

  void _onForegroundChanged(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    AppLog.d(_tag, 'foreground=$foreground, adjusting poll cadence');
    if (state.sessions.isEmpty) return;
    if (foreground) {
      _pollTimer?.cancel();
      _lastRosterRefresh = DateTime.fromMillisecondsSinceEpoch(0);
      _scheduleNextPoll(Duration.zero);
    } else {
      _pollTimer?.cancel();
      _scheduleNextPoll();
    }
  }

  // ─── Encrypted chat history ───────────────────────────────────────

  static const _historyEnabledKey = 'chat_history_enabled';
  static const _historyRetentionKey = 'chat_history_retention_days';

  Future<void> loadHistoryPreferences() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_historyEnabledKey) ?? false;
    final retention = HistoryRetention.fromDays(
      prefs.getInt(_historyRetentionKey) ?? HistoryRetention.thirtyDays.days,
    );
    // Apply to every session so the setting is consistent across servers.
    for (final cid in state.sessions.keys) {
      _setSession(
        cid,
        _stateOf(
          cid,
        ).copyWith(chatHistoryEnabled: enabled, chatRetention: retention),
      );
    }
  }

  Future<void> setChatHistoryEnabled(int cid, bool enabled) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setBool(_historyEnabledKey, enabled);
    for (final scid in state.sessions.keys) {
      _setSession(scid, _stateOf(scid).copyWith(chatHistoryEnabled: enabled));
    }
    if (!enabled) {
      for (final scid in state.sessions.keys) {
        _rt[scid]?.historySaveTimer?.cancel();
      }
      await ChatHistoryService.clearAll();
      AppLog.i(_tag, 'chat history disabled and cleared');
    }
  }

  Future<void> setChatRetention(int cid, HistoryRetention retention) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setInt(_historyRetentionKey, retention.days);
    for (final scid in state.sessions.keys) {
      _setSession(scid, _stateOf(scid).copyWith(chatRetention: retention));
      if (_stateOf(scid).chatHistoryEnabled) {
        _scheduleHistorySave(scid, immediate: true);
      }
    }
  }

  Future<int> clearChatHistory() async {
    for (final scid in state.sessions.keys) {
      _rt[scid]?.historySaveTimer?.cancel();
    }
    return ChatHistoryService.clearAll();
  }

  Future<void> _restoreHistory(int cid) async {
    final st = _stateOf(cid);
    if (!st.chatHistoryEnabled || st.serverUid.isEmpty) return;
    final stored = await ChatHistoryService.load(
      st.serverUid,
      retention: st.chatRetention,
    );
    if (stored.isEmpty) return;
    _setSession(cid, st.copyWith(messages: [...stored, ...st.messages]));
    AppLog.i(_tag, 'restored ${stored.length} stored messages');
  }

  void _scheduleHistorySave(int cid, {bool immediate = false}) {
    final st = _stateOf(cid);
    if (!st.chatHistoryEnabled || st.serverUid.isEmpty) return;
    final rt = _rt[cid];
    rt?.historySaveTimer?.cancel();
    final delay = immediate ? Duration.zero : const Duration(seconds: 3);
    rt?.historySaveTimer = Timer(delay, () {
      ChatHistoryService.save(
        st.serverUid,
        st.messages,
        retention: st.chatRetention,
      );
    });
  }

  // ─── Secret erasure (global) ──────────────────────────────────────

  Future<bool> eraseIdentityAndSecrets() async {
    var ok = true;
    for (final cid in state.order.toList()) {
      final st = _stateOf(cid);
      if (st.connected || st.connecting) disconnect(cid);
    }
    TsNative.clearIdentity();
    try {
      await SecureStorage.delete(SecureStorage.identityKey);
    } catch (error) {
      AppLog.w(_tag, 'identity delete reported an error');
      ok = false;
    }
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.remove('client_identity');
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith('client_volume_uid_') ||
          key == 'whisper_allowed_uids') {
        await prefs.remove(key);
      }
    }
    await ChatHistoryService.clearAll();
    for (final cid in state.sessions.keys) {
      _setSession(cid, _stateOf(cid).copyWith(whisperAllowedUids: const []));
      TsNative.setWhisperAllowlist(cid, const []);
    }
    AppLog.i(_tag, 'identity and local secrets erased (ok=$ok)');
    return ok;
  }

  // ─── Audio routing & platform effects (global) ────────────────────

  static const _aecKey = 'audio_effect_aec';
  static const _nsKey = 'audio_effect_ns';
  static const _agcKey = 'audio_effect_agc';
  static const _routeKey = 'audio_route';

  Future<void> loadAudioPreferences() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final support = await AudioRouteService.effectAvailability();
    final routes = await AudioRouteService.availableRoutes();
    final aec = (prefs.getBool(_aecKey) ?? true) && support.aec;
    final ns = (prefs.getBool(_nsKey) ?? true) && support.ns;
    final agc = (prefs.getBool(_agcKey) ?? false) && support.agc;
    var route = AudioRoute.fromId(prefs.getString(_routeKey) ?? 'auto');
    if (!routes.contains(route)) route = AudioRoute.auto;
    await AudioRouteService.setEffects(aec: aec, ns: ns, agc: agc);
    final applied = await AudioRouteService.setRoute(route);
    for (final cid in state.sessions.keys) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(
          effectSupport: support,
          availableRoutes: routes,
          aecEnabled: aec,
          nsEnabled: ns,
          agcEnabled: agc,
          audioRoute: applied,
        ),
      );
    }
  }

  Future<void> refreshAudioRoutes() async {
    final routes = await AudioRouteService.availableRoutes();
    for (final cid in state.sessions.keys) {
      var route = _stateOf(cid).audioRoute;
      if (!routes.contains(route)) route = AudioRoute.auto;
      _setSession(
        cid,
        _stateOf(cid).copyWith(availableRoutes: routes, audioRoute: route),
      );
    }
  }

  Future<void> setAudioRoute(AudioRoute route) async {
    final applied = await AudioRouteService.setRoute(route);
    _prefs?.setString(_routeKey, applied.id);
    for (final cid in state.sessions.keys) {
      _setSession(cid, _stateOf(cid).copyWith(audioRoute: applied));
    }
  }

  Future<void> setAudioEffects({bool? aec, bool? ns, bool? agc}) async {
    final support = state.selected.effectSupport;
    final nextAec = (aec ?? state.selected.aecEnabled) && support.aec;
    final nextNs = (ns ?? state.selected.nsEnabled) && support.ns;
    final nextAgc = (agc ?? state.selected.agcEnabled) && support.agc;
    await AudioRouteService.setEffects(aec: nextAec, ns: nextNs, agc: nextAgc);
    _prefs?.setBool(_aecKey, nextAec);
    _prefs?.setBool(_nsKey, nextNs);
    _prefs?.setBool(_agcKey, nextAgc);
    for (final cid in state.sessions.keys) {
      _setSession(
        cid,
        _stateOf(
          cid,
        ).copyWith(aecEnabled: nextAec, nsEnabled: nextNs, agcEnabled: nextAgc),
      );
    }
  }

  // ─── Connection state machine & reconnection (per session) ───────

  static String _connectErrorMessage(String kind, String detail) =>
      switch (kind) {
        'dns' => 'Server address could not be resolved',
        'timeout' => 'The server did not answer in time',
        'network' => 'Network error while contacting the server',
        'password' => 'Wrong server password',
        'channel_password' => 'Wrong channel password',
        'banned' => 'You are banned from this server',
        'nickname_in_use' => 'This nickname is already in use',
        'identity_level' =>
          'The server requires a higher identity security level',
        'server_full' => 'The server is full',
        'server_identity_changed' =>
          'The server changed its identity key; connection refused',
        'server_refused' => 'The server refused the connection',
        'protocol' => 'Unexpected server response',
        'cancelled' => 'Connection cancelled',
        'connection_lost' => 'Connection lost',
        _ => detail,
      };

  void cancelConnect(int cid) {
    _rt[cid]?.reconnectTimer?.cancel();
    _rt[cid]?.autoReconnect = true;
    _rt[cid]?.lastRequest = null;
    TsNative.cancelConnect(cid);
    final sessions = Map<int, TsConnectionState>.from(state.sessions)
      ..remove(cid);
    final order = state.order.where((c) => c != cid).toList();
    _rt.remove(cid);
    state = state.copyWith(
      sessions: sessions,
      order: order,
      selectedId: order.isEmpty ? null : state.selectedId,
    );
    _refreshNotification();
    if (state.sessions.isEmpty) _pollTimer?.cancel();
  }

  void retryNow(int cid) {
    final rt = _rt[cid];
    final request = rt?.lastRequest;
    if (rt == null || request == null) return;
    rt.reconnectTimer?.cancel();
    final pending = _stateOf(cid).reconnectAttempt;
    connect(
      address: request.address,
      nickname: request.nickname,
      channel: rt.channelToRestore ?? request.channel,
      password: request.password,
      channelPassword: request.channelPassword,
    );
    _setSession(cid, _stateOf(cid).copyWith(reconnectAttempt: pending));
  }

  void setAutoReconnect(int cid, bool enabled) {
    final rt = _rt[cid];
    if (rt == null) return;
    rt.autoReconnect = enabled;
    _prefs?.setBool('auto_reconnect', enabled);
    if (!enabled) rt.reconnectTimer?.cancel();
    _setSession(
      cid,
      _stateOf(cid).copyWith(
        autoReconnectEnabled: enabled,
        reconnectAttempt: enabled ? _stateOf(cid).reconnectAttempt : 0,
        reconnectAt: enabled ? _stateOf(cid).reconnectAt : null,
      ),
    );
  }

  Future<void> loadReconnectPreference() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final enabled = prefs.getBool('auto_reconnect') ?? true;
    for (final cid in state.sessions.keys) {
      final rt = _rt[cid];
      if (rt != null) {
        rt.autoReconnect = enabled;
        _setSession(cid, _stateOf(cid).copyWith(autoReconnectEnabled: enabled));
      }
    }
  }

  void _maybeScheduleReconnect(
    int cid, {
    required String kind,
    required bool retryable,
  }) {
    final rt = _rt[cid];
    final request = rt?.lastRequest;
    if (rt == null || request == null || !rt.autoReconnect) return;
    final attempt = _stateOf(cid).reconnectAttempt;
    if (!ReconnectPolicy.shouldRetry(
      kind: kind,
      retryable: retryable,
      attempt: attempt,
    )) {
      AppLog.i(_tag, 'no reconnect (kind=$kind, attempt=$attempt)');
      _setSession(
        cid,
        _stateOf(cid).copyWith(reconnectAttempt: 0, reconnectAt: null),
      );
      return;
    }
    if (!_network.available) {
      AppLog.i(_tag, 'offline, waiting for connectivity before retrying');
      _setSession(
        cid,
        _stateOf(cid).copyWith(
          phase: TsPhase.reconnecting,
          reconnectAttempt: attempt + 1,
          reconnectAt: null,
        ),
      );
      return;
    }
    final delay = ReconnectPolicy.delayFor(attempt);
    AppLog.i(_tag, 'reconnect #${attempt + 1} in ${delay.inMilliseconds}ms');
    rt.reconnectTimer?.cancel();
    _setSession(
      cid,
      _stateOf(cid).copyWith(
        phase: TsPhase.reconnecting,
        reconnectAttempt: attempt + 1,
        reconnectAt: DateTime.now().add(delay),
      ),
    );
    rt.reconnectTimer = Timer(delay, () {
      if (!(rt.autoReconnect)) return;
      final pending = _stateOf(cid).reconnectAttempt;
      connect(
        address: request.address,
        nickname: request.nickname,
        channel: rt.channelToRestore ?? request.channel,
        password: request.password,
        channelPassword: request.channelPassword,
      );
      _setSession(cid, _stateOf(cid).copyWith(reconnectAttempt: pending));
    });
  }

  void _restoreChannelAfterReconnect(int cid, List<TsChannel> channels) {
    final rt = _rt[cid];
    final target = rt?.channelToRestore;
    if (rt == null) return;
    rt.channelToRestore = null;
    if (target == null || target.isEmpty) return;
    if (_currentChannelName(cid) == target) return;
    final match = channels.where((c) => c.name == target).firstOrNull;
    if (match == null) {
      AppLog.i(_tag, 'saved channel is gone, staying in the default one');
      return;
    }
    AppLog.i(_tag, 'restoring the pre-drop channel');
    selectChannel(cid, match.id);
  }

  // ─── Whisper (per session) ────────────────────────────────────────

  static const _whisperAllowModeKey = 'whisper_allowlist_enabled';
  static const _whisperAllowedUidsKey = 'whisper_allowed_uids';

  Future<void> applyWhisperPreferences(int cid) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_whisperAllowModeKey) ?? false;
    final uids =
        prefs.getStringList(_whisperAllowedUidsKey) ?? const <String>[];
    TsNative.setWhisperAllowlist(cid, uids);
    TsNative.setWhisperAllowlistEnabled(cid, enabled);
    _setSession(
      cid,
      _stateOf(cid).copyWith(
        whisperAllowlistEnabled: enabled,
        whisperAllowedUids: uids,
        whisperActive: false,
        whisperTargetClientIds: const [],
        whisperTargetChannelIds: const [],
        whisperIgnoredCount: 0,
      ),
    );
  }

  void setWhisperTargets({
    required int cid,
    required List<int> clientIds,
    required List<int> channelIds,
  }) {
    final st = _stateOf(cid);
    final clients =
        clientIds.where((id) => id != st.ownClientId).toSet().toList()..sort();
    final channels = channelIds.toSet().toList()..sort();
    TsNative.setWhisperTargets(
      connectionId: cid,
      clientIds: clients,
      channelIds: channels,
    );
    final hasTarget = clients.isNotEmpty || channels.isNotEmpty;
    if (!hasTarget && st.whisperActive) {
      TsNative.setWhisperActive(cid, false);
    }
    _setSession(
      cid,
      st.copyWith(
        whisperTargetClientIds: clients,
        whisperTargetChannelIds: channels,
        whisperActive: hasTarget && st.whisperActive,
      ),
    );
  }

  void setWhisperActive(int cid, bool active) {
    final st = _stateOf(cid);
    if (active && !st.hasWhisperTargets) {
      _setSession(
        cid,
        st.copyWith(error: 'Select at least one whisper target first'),
      );
      return;
    }
    if (!TsNative.setWhisperActive(cid, active)) {
      if (active) return;
    }
    _setSession(cid, st.copyWith(whisperActive: active));
  }

  void toggleWhisperActive(int cid) =>
      setWhisperActive(cid, !_stateOf(cid).whisperActive);

  void setWhisperAllowlistEnabled(int cid, bool enabled) {
    TsNative.setWhisperAllowlistEnabled(cid, enabled);
    _prefs?.setBool(_whisperAllowModeKey, enabled);
    _setSession(cid, _stateOf(cid).copyWith(whisperAllowlistEnabled: enabled));
  }

  void toggleWhisperAllowedUid(int cid, String uid) {
    if (uid.isEmpty) return;
    final st = _stateOf(cid);
    final uids = [...st.whisperAllowedUids];
    if (!uids.remove(uid)) uids.add(uid);
    uids.sort();
    TsNative.setWhisperAllowlist(cid, uids);
    _prefs?.setStringList(_whisperAllowedUidsKey, uids);
    _setSession(cid, st.copyWith(whisperAllowedUids: uids));
  }

  void _pruneWhisperTargets(int cid) {
    final st = _stateOf(cid);
    if (st.whisperTargetClientIds.isEmpty &&
        st.whisperTargetChannelIds.isEmpty) {
      return;
    }
    final liveClients = st.clients.map((c) => c.id).toSet();
    final liveChannels = st.channels.map((c) => c.id).toSet();
    final clients = st.whisperTargetClientIds
        .where(liveClients.contains)
        .toList();
    final channels = st.whisperTargetChannelIds
        .where(liveChannels.contains)
        .toList();
    if (clients.length == st.whisperTargetClientIds.length &&
        channels.length == st.whisperTargetChannelIds.length) {
      return;
    }
    setWhisperTargets(cid: cid, clientIds: clients, channelIds: channels);
  }

  DateTime _lastWhisperStats = DateTime.fromMillisecondsSinceEpoch(0);
  static const _whisperStatsThrottle = Duration(seconds: 3);

  void _refreshWhisperStats(int cid) {
    // The allow-list counter changes rarely; calling getWhisperStatus (an FFI
    // round-trip + JSON decode) on every roster reconcile was pure overhead.
    if (!_stateOf(cid).whisperAllowlistEnabled) return;
    final now = DateTime.now();
    if (now.difference(_lastWhisperStats) < _whisperStatsThrottle) return;
    _lastWhisperStats = now;
    try {
      final status =
          jsonDecode(TsNative.getWhisperStatus(cid)) as Map<String, dynamic>;
      final ignored = status['ignored_count'] as int? ?? 0;
      if (ignored != _stateOf(cid).whisperIgnoredCount) {
        _setSession(cid, _stateOf(cid).copyWith(whisperIgnoredCount: ignored));
      }
    } catch (error) {
      AppLog.e(_tag, 'whisper status read failed', error);
    }
  }

  void _migrateLegacyVolumeKeys() {
    final prefs = _prefs;
    if (prefs == null) return;
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith('client_volume_')) continue;
      final suffix = key.substring('client_volume_'.length);
      if (int.tryParse(suffix) != null) {
        prefs.remove(key);
      }
    }
  }

  void _applySavedClientVolumes(int cid) {
    final prefs = _prefs;
    if (prefs == null) return;
    for (final client in _stateOf(cid).clients) {
      final uid = client.uid;
      if (uid == null || uid.isEmpty) continue;
      final saved = prefs.getDouble('client_volume_uid_$uid');
      if (saved != null && (saved - client.volume).abs() > 0.001) {
        setClientVolume(cid, client.id, saved);
      }
    }
    // Apply the contact book (muted / volumeModifier) to the live roster,
    // when the client has a saved contact for this server. A muted contact is
    // silenced by dropping the gain to its minimum; a custom volumeModifier
    // (dB) overrides the per-client volume.
    if (!_stateOf(cid).connected) return;
    final serverUid = _stateOf(cid).serverUid;
    if (serverUid.isEmpty) return;
    for (final client in _stateOf(cid).clients) {
      final uid = client.uid;
      if (uid == null || uid.isEmpty) continue;
      _applyContactToClient(cid, serverUid, client);
    }
  }

  /// Looks up the persisted contact (if any) for a live client on this server.
  ///
  /// The contact book is keyed by `contact_<server_uid>_<uid>`. Returns null
  /// when the client has no saved contact or the record is malformed, so every
  /// caller can fail open (treat an unknown client as a normal user).
  ContactSettings? _contactForClient(int cid, int clientId) {
    final prefs = _prefs;
    if (prefs == null) return null;
    final st = _stateOf(cid);
    final serverUid = st.serverUid;
    if (serverUid.isEmpty) return null;
    final client = st.clients.where((c) => c.id == clientId).firstOrNull;
    final uid = client?.uid;
    if (uid == null || uid.isEmpty) return null;
    final raw = prefs.getString('contact_${serverUid}_$uid');
    if (raw == null) return null;
    try {
      return ContactSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Applies one contact's persisted settings to a live client.
  void _applyContactToClient(int cid, String serverUid, TsClient client) {
    final uid = client.uid;
    if (uid == null || uid.isEmpty) return;
    // ContactStore.load is async; the roster reconcile already runs off the
    // poll loop. Persisted mute/volume is applied lazily by reading the
    // SharedPreferences key directly (same source as ContactStore).
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final raw = prefs.getString('contact_${serverUid}_$uid');
      if (raw == null) return;
      final settings = ContactSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      var volumeDb = settings.volumeModifier;
      if (settings.muted) volumeDb = -20.0; // full silence for a muted contact
      if ((volumeDb - client.volume).abs() > 0.001) {
        setClientVolume(cid, client.id, volumeDb);
      }
    } catch (_) {
      // Malformed or absent contact → ignore.
    }
  }

  // ─── Channel comfort: favorites, sort, event sounds ───────────────

  static const _eventSoundsKey = 'event_sounds_enabled';
  static String _channelFavKey(String serverUid, int channelId) =>
      'channel_fav_${serverUid}_$channelId';
  static String _channelSortKey(String serverUid) =>
      'channel_sort_alpha_$serverUid';

  /// Loads the per-server "sort alphabetically" toggle and the global event
  /// sounds preference. Called once the server handshake completes (the
  /// serverUid is then known).
  Future<void> loadChannelUiPrefs(int cid) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final st = _stateOf(cid);
    final sortAlpha = st.serverUid.isNotEmpty
        ? prefs.getBool(_channelSortKey(st.serverUid)) ?? false
        : false;
    final sounds = prefs.getBool(_eventSoundsKey) ?? false;
    // Rebuild the favorite set from the persisted keys for this server.
    final favorites = <int>{};
    if (st.serverUid.isNotEmpty) {
      final prefix = 'channel_fav_${st.serverUid}_';
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith(prefix)) {
          final suffix = key.substring(prefix.length);
          final id = int.tryParse(suffix);
          if (id != null && (prefs.getBool(key) ?? false)) favorites.add(id);
        }
      }
    }
    _setSession(
      cid,
      st.copyWith(
        channelsSortedAlpha: sortAlpha,
        eventSoundsEnabled: sounds,
        favoriteChannelIds: favorites,
      ),
    );
  }

  /// Pins/unpins a channel for this server. Persisted keyed by the server UID
  /// so it is meaningful across sessions.
  void toggleChannelFavorite(int cid, int channelId) {
    final st = _stateOf(cid);
    final favorites = Set<int>.from(st.favoriteChannelIds);
    final isFav = !favorites.remove(channelId);
    if (isFav) favorites.add(channelId);
    final prefs = _prefs;
    if (prefs != null && st.serverUid.isNotEmpty) {
      prefs.setBool(_channelFavKey(st.serverUid, channelId), isFav);
    }
    _setSession(cid, st.copyWith(favoriteChannelIds: favorites));
  }

  /// Switches the channel tree between alphabetical and server order.
  void setChannelSortAlpha(int cid, bool alpha) {
    final prefs = _prefs;
    if (prefs != null && _stateOf(cid).serverUid.isNotEmpty) {
      prefs.setBool(_channelSortKey(_stateOf(cid).serverUid), alpha);
    }
    _setSession(cid, _stateOf(cid).copyWith(channelsSortedAlpha: alpha));
  }

  /// Enables/disables the sound played on an unseen message.
  Future<void> setEventSounds(bool enabled) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setBool(_eventSoundsKey, enabled);
    for (final cid in state.sessions.keys) {
      _setSession(cid, _stateOf(cid).copyWith(eventSoundsEnabled: enabled));
    }
  }

  /// Plays the event sound once — guarded by the user preference, and only
  /// for a message in a conversation that is not currently on screen, so a
  /// busy channel the user is watching does not beep on every line.
  void _maybePlayEventSound(int cid, ChatThreadKey threadKey) {
    if (!_stateOf(cid).eventSoundsEnabled) return;
    if (_rt[cid]?.openThread == threadKey.value) return;
    SystemSound.play(SystemSoundType.alert);
  }

  /// Adds/updates an in-flight transfer in the session's live list.
  void _upsertTransfer(int cid, FileTransfer transfer) {
    final transfers = List<FileTransfer>.from(_stateOf(cid).transfers);
    final idx = transfers.indexWhere(
      (t) => t.transferId == transfer.transferId,
    );
    if (idx >= 0) {
      transfers[idx] = transfer;
    } else {
      transfers.add(transfer);
    }
    _setSession(cid, _stateOf(cid).copyWith(transfers: transfers));
  }

  // ─── File upload & channel administration ─────────────────────────

  /// Uploads a local file to a server channel. [remotePath] is the server-side
  /// target (must start with `/`). Progress arrives as `file_transfer_progress`
  /// events; a final `file_transfer` clears the entry and reports the result.
  void uploadFile(
    int cid, {
    required String remotePath,
    required String sourcePath,
    int channelId = 0,
    String? channelPassword,
    bool overwrite = false,
  }) {
    if (!_stateOf(cid).connected) return;
    final id = TsNative.uploadFile(
      connectionId: cid,
      channelId: channelId,
      remotePath: remotePath,
      sourcePath: sourcePath,
      channelPassword: channelPassword,
      overwrite: overwrite,
    );
    if (id == 0) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(error: 'Unable to start the upload'),
      );
      return;
    }
    _upsertTransfer(
      cid,
      FileTransfer(
        transferId: id,
        remotePath: remotePath,
        totalBytes: _fileSize(sourcePath),
        direction: FileTransferDirection.upload,
      ),
    );
  }

  static int _fileSize(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return 0;
    }
  }

  void createChannel(
    int cid, {
    required int parentId,
    required String name,
    String? topic,
    String? description,
    String? password,
    int? maxClients,
    bool permanent = false,
    bool semiPermanent = false,
  }) {
    if (!_stateOf(cid).connected) return;
    if (!TsNative.createChannel(
      connectionId: cid,
      parentId: parentId,
      name: name,
      topic: topic,
      description: description,
      password: password,
      maxClients: maxClients,
      permanent: permanent,
      semiPermanent: semiPermanent,
    )) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(error: 'Unable to create the channel'),
      );
    }
  }

  void editChannel(
    int cid, {
    required int channelId,
    String? name,
    String? topic,
    String? description,
    String? password,
    bool? hasPassword,
    int? maxClients,
    bool? permanent,
    bool? semiPermanent,
  }) {
    if (!_stateOf(cid).connected) return;
    if (!TsNative.editChannel(
      connectionId: cid,
      channelId: channelId,
      name: name,
      topic: topic,
      description: description,
      password: password,
      hasPassword: hasPassword,
      maxClients: maxClients,
      permanent: permanent,
      semiPermanent: semiPermanent,
    )) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(error: 'Unable to edit the channel'),
      );
    }
  }

  void deleteChannel(int cid, int channelId, {bool force = false}) {
    if (!_stateOf(cid).connected) return;
    if (!TsNative.deleteChannel(
      connectionId: cid,
      channelId: channelId,
      force: force,
    )) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(error: 'Unable to delete the channel'),
      );
    }
  }

  void moveChannelTree(int cid, int channelId, int parentId, {int? order}) {
    if (!_stateOf(cid).connected) return;
    if (!TsNative.moveChannelTree(
      connectionId: cid,
      channelId: channelId,
      parentId: parentId,
      order: order,
    )) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(error: 'Unable to move the channel'),
      );
    }
  }

  // ─── File browser (ftgetfilelist / ftdeletefile / ftcreatedir) ─────

  /// Requests a file listing of [path] in the channel currently selected on
  /// [cid] (or channel 0 for the root when none is selected).
  void listChannelFiles(int cid, {String path = '/'}) {
    final st = _stateOf(cid);
    if (!st.connected) return;
    final channelId = st.selectedChannelId ?? 0;
    final requestId = TsNative.listFiles(
      connectionId: cid,
      channelId: channelId,
      path: path,
    );
    if (requestId == 0) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(
          serverFilesLoading: false,
          serverFilesError: 'Unable to list files',
        ),
      );
      return;
    }
    _lastFileRequestId[cid] = requestId;
    _setSession(
      cid,
      _stateOf(cid).copyWith(
        serverFilePath: path,
        serverFilesLoading: true,
        serverFilesError: null,
      ),
    );
  }

  /// Re-lists the directory currently shown in the file browser of [cid].
  void refreshFilePanel(int cid) {
    listChannelFiles(cid, path: _stateOf(cid).serverFilePath);
  }

  /// Deletes a file on the server, then re-lists the current directory.
  void deleteServerFile(int cid, String path) {
    if (!_stateOf(cid).connected) return;
    final channelId = _stateOf(cid).selectedChannelId ?? 0;
    TsNative.deleteFile(connectionId: cid, channelId: channelId, path: path);
    refreshFilePanel(cid);
  }

  /// Creates a directory on the server, then re-lists the current directory.
  void createChannelDirectory(int cid, String path) {
    if (!_stateOf(cid).connected) return;
    final channelId = _stateOf(cid).selectedChannelId ?? 0;
    TsNative.createDirectory(
      connectionId: cid,
      channelId: channelId,
      path: path,
    );
    refreshFilePanel(cid);
  }

  /// Cancels an in-flight transfer (best effort: only a transfer that has not
  /// begun streaming is actually cancelled).
  bool cancelTransfer(int cid, int transferId) {
    final ok = TsNative.cancelFileTransfer(cid, transferId) != 0;
    if (ok) {
      _setSession(
        cid,
        _stateOf(cid).copyWith(
          transfers: _stateOf(
            cid,
          ).transfers.where((t) => t.transferId != transferId).toList(),
        ),
      );
    }
    return ok;
  }

  // ─── Microphone & notification ────────────────────────────────────

  bool get _shouldMicBeActive {
    final cid = _micConnectionId;
    if (cid == 0) return false;
    final st = _stateOf(cid);
    if (st.pttMode) return st.pttPressed;
    return !st.inputMuted;
  }

  void _startAudioService() {
    final cid = _micConnectionId;
    if (cid == 0) return;
    _audioService = AudioService()..connectionId = cid;
    _audioService!.onMicLevel = (double rms) {
      // Mic frames arrive ~50×/s; writing the level to state that often
      // rebuilds the whole server screen and overheats the phone. The level is
      // only shown on the mic-activity slider, so 10 updates/s is plenty —
      // and only when the value actually moved by a perceptible amount.
      final micCid = _micConnectionId;
      if (micCid == 0) return;
      final now = DateTime.now();
      if (now.difference(_lastMicLevelWrite) < _micLevelThrottle) return;
      final prev = _stateOf(micCid).micRms;
      if ((rms - prev).abs() < 0.002) return;
      _lastMicLevelWrite = now;
      _setSession(micCid, _stateOf(micCid).copyWith(micRms: rms));
    };
    _audioService!.start();
  }

  void _updateMicState() {
    // The active tab owns the (single) device microphone, so keep the service
    // pointed at whichever session is focused.
    if (_audioService != null) {
      _audioService!.connectionId = _micConnectionId;
    }
    if (_audioService == null) {
      if (_shouldMicBeActive) _startAudioService();
      return;
    }
    final should = _shouldMicBeActive;
    if (should && !_micEnabled) {
      _audioService!.enableMic().then((granted) {
        if (granted) {
          _micGranted = true;
        }
      });
      _micEnabled = true;
    } else if (!should && _micEnabled) {
      _audioService!.disableMic();
      _micEnabled = false;
      _micGranted = false;
    }
  }

  String get _notifMuteLabel =>
      ref.read(localeProvider.notifier).localizations?.notifMute ?? 'Mute';
  String get _notifUnmuteLabel =>
      ref.read(localeProvider.notifier).localizations?.notifUnmute ?? 'Unmute';
  String get _notifDisconnectLabel =>
      ref.read(localeProvider.notifier).localizations?.notifDisconnect ??
      'Disconnect';

  bool _notificationStarted = false;

  void _refreshNotification({bool? mic}) {
    // The notification is a platform channel call; rapid callers (voice-active
    // toggles every poll, mute/unmute taps) would otherwise serialize a flood.
    // Coalesce to at most one update per ~600ms — the notification content only
    // changes on meaningful transitions, so intermediate states are dropped.
    final now = DateTime.now();
    if (_notificationStarted &&
        now.difference(_lastNotification) < _notifyThrottle) {
      return;
    }
    _lastNotification = now;

    var connectedCount = 0;
    var anyInputMuted = false;
    var anyVoice = false;
    var allMuted = true;
    final names = <String>[];
    for (final s in state.sessions.values) {
      if (!s.connected) continue;
      connectedCount++;
      anyInputMuted = anyInputMuted || s.inputMuted;
      anyVoice = anyVoice || s.voiceActive;
      allMuted = allMuted && s.inputMuted && s.outputMuted;
      if (names.length < 2 && s.serverName.isNotEmpty) names.add(s.serverName);
    }
    if (connectedCount == 0) {
      _notificationStarted = false;
      ForegroundService.stop();
      return;
    }
    final title = connectedCount == 1
        ? (names.isNotEmpty ? names.first : 'TeamSpeak')
        : '$connectedCount servers';
    var text = names.isNotEmpty ? names.join(' \u2022 ') : 'server';
    if (!anyInputMuted || anyVoice) {
      text = '$text \u2014 Speaking';
    }
    final micVal = mic ?? _micGranted;
    if (!_notificationStarted) {
      _notificationStarted = true;
      ForegroundService.start(
        title: title,
        text: text,
        mic: micVal,
        inputMuted: anyInputMuted,
        fullMuted: allMuted,
        muteLabel: _notifMuteLabel,
        unmuteLabel: _notifUnmuteLabel,
        disconnectLabel: _notifDisconnectLabel,
      );
    } else {
      ForegroundService.update(
        title: title,
        text: text,
        mic: micVal,
        inputMuted: anyInputMuted,
        fullMuted: allMuted,
        muteLabel: _notifMuteLabel,
        unmuteLabel: _notifUnmuteLabel,
        disconnectLabel: _notifDisconnectLabel,
      );
    }
  }

  static String _tabLabel(String address, String nickname) {
    final host = address.split(':').first;
    if (nickname.isNotEmpty) return '$host ($nickname)';
    return host;
  }
}

// ─── Per-session facade for the UI ─────────────────────────────────

/// A thin, per-session handle that lets widgets issue actions against one
/// server without threading a `connectionId` through every call.
class TsConnectionNotifier {
  final MultiServerNotifier _controller;
  final int connectionId;

  TsConnectionNotifier(this._controller, this.connectionId);

  void sendChannelMessage(String text) =>
      _controller.sendChannelMessage(connectionId, text);
  void sendServerMessage(String text) =>
      _controller.sendServerMessage(connectionId, text);
  void sendPrivateMessage(int clientId, String text) =>
      _controller.sendPrivateMessage(connectionId, clientId, text);
  bool selectChannel(int channelId, {String? password}) =>
      _controller.selectChannel(connectionId, channelId, password: password);

  void toggleInputMute() => _controller.toggleInputMute(connectionId);
  void setFullMute(bool muted) => _controller.setFullMute(connectionId, muted);
  void toggleFullMute() => _controller.toggleFullMute(connectionId);
  void toggleOutputMute() => _controller.toggleOutputMute(connectionId);
  void togglePttMode() => _controller.togglePttMode(connectionId);
  void setPttPressed(bool pressed) =>
      _controller.setPttPressed(connectionId, pressed);
  void setVadEnabled(bool enabled) =>
      _controller.setVadEnabled(connectionId, enabled);
  void setVadThreshold(double threshold) =>
      _controller.setVadThreshold(connectionId, threshold);
  void setMicGain(double gain) => _controller.setMicGain(connectionId, gain);
  void setClientVolume(int clientId, double volumeDb) =>
      _controller.setClientVolume(connectionId, clientId, volumeDb);

  void kickClient(int clientId, {required bool fromServer, String? reason}) =>
      _controller.kickClient(
        connectionId,
        clientId,
        fromServer: fromServer,
        reason: reason,
      );
  void banClient(int clientId, {int seconds = 0, String? reason}) => _controller
      .banClient(connectionId, clientId, seconds: seconds, reason: reason);
  void pokeClient(int clientId, String message) =>
      _controller.pokeClient(connectionId, clientId, message);
  void moveClient(int clientId, int channelId, {String? password}) =>
      _controller.moveClient(
        connectionId,
        clientId,
        channelId,
        password: password,
      );

  void setAway(bool away, {String? message}) =>
      _controller.setAway(connectionId, away, message: message);
  bool setNickname(String nickname) =>
      _controller.setNickname(connectionId, nickname);
  void setChannelCommander(bool enabled) =>
      _controller.setChannelCommander(connectionId, enabled);

  void setWhisperTargets({
    required List<int> clientIds,
    required List<int> channelIds,
  }) => _controller.setWhisperTargets(
    cid: connectionId,
    clientIds: clientIds,
    channelIds: channelIds,
  );
  void setWhisperActive(bool active) =>
      _controller.setWhisperActive(connectionId, active);
  void toggleWhisperActive() => _controller.toggleWhisperActive(connectionId);
  void setWhisperAllowlistEnabled(bool enabled) =>
      _controller.setWhisperAllowlistEnabled(connectionId, enabled);
  void toggleWhisperAllowedUid(String uid) =>
      _controller.toggleWhisperAllowedUid(connectionId, uid);

  void openThread(ChatThreadKey key) =>
      _controller.openThread(connectionId, key);
  void closeThreads() => _controller.closeThreads(connectionId);
  ChatThreadKey openPrivateThread(int clientId) =>
      _controller.openPrivateThread(connectionId, clientId);

  // Channel comfort: favorites, sort, event sounds.
  void toggleChannelFavorite(int channelId, bool favorite) =>
      _controller.toggleChannelFavorite(connectionId, channelId);
  void setChannelSortAlpha(bool alpha) =>
      _controller.setChannelSortAlpha(connectionId, alpha);
  Future<void> setEventSounds(bool enabled) =>
      _controller.setEventSounds(enabled);

  // File upload & channel administration.
  void uploadFile({
    required String remotePath,
    required String sourcePath,
    int channelId = 0,
    String? channelPassword,
    bool overwrite = false,
  }) => _controller.uploadFile(
    connectionId,
    remotePath: remotePath,
    sourcePath: sourcePath,
    channelId: channelId,
    channelPassword: channelPassword,
    overwrite: overwrite,
  );
  bool cancelTransfer(int transferId) =>
      _controller.cancelTransfer(connectionId, transferId);

  // File browser.
  void listChannelFiles({String path = '/'}) =>
      _controller.listChannelFiles(connectionId, path: path);
  void refreshFilePanel() => _controller.refreshFilePanel(connectionId);
  void deleteServerFile(String path) =>
      _controller.deleteServerFile(connectionId, path);
  void createChannelDirectory(String path) =>
      _controller.createChannelDirectory(connectionId, path);
  void createChannel({
    required int parentId,
    required String name,
    String? topic,
    String? description,
    String? password,
    int? maxClients,
    bool permanent = false,
    bool semiPermanent = false,
  }) => _controller.createChannel(
    connectionId,
    parentId: parentId,
    name: name,
    topic: topic,
    description: description,
    password: password,
    maxClients: maxClients,
    permanent: permanent,
    semiPermanent: semiPermanent,
  );
  void editChannel({
    required int channelId,
    String? name,
    String? topic,
    String? description,
    String? password,
    bool? hasPassword,
    int? maxClients,
    bool? permanent,
    bool? semiPermanent,
  }) => _controller.editChannel(
    connectionId,
    channelId: channelId,
    name: name,
    topic: topic,
    description: description,
    password: password,
    hasPassword: hasPassword,
    maxClients: maxClients,
    permanent: permanent,
    semiPermanent: semiPermanent,
  );
  void deleteChannel(int channelId, {bool force = false}) =>
      _controller.deleteChannel(connectionId, channelId, force: force);
  void moveChannelTree(int channelId, int parentId, {int? order}) => _controller
      .moveChannelTree(connectionId, channelId, parentId, order: order);

  void disconnect() => _controller.disconnect(connectionId);
  void retryNow() => _controller.retryNow(connectionId);
  void cancelConnect() => _controller.cancelConnect(connectionId);
  void setAutoReconnect(bool enabled) =>
      _controller.setAutoReconnect(connectionId, enabled);

  // Global preferences, applied across sessions.
  Future<void> loadAudioPreferences() => _controller.loadAudioPreferences();
  Future<void> refreshAudioRoutes() => _controller.refreshAudioRoutes();
  Future<void> setAudioRoute(AudioRoute route) =>
      _controller.setAudioRoute(route);
  Future<void> setAudioEffects({bool? aec, bool? ns, bool? agc}) =>
      _controller.setAudioEffects(aec: aec, ns: ns, agc: agc);
  Future<void> loadHistoryPreferences() => _controller.loadHistoryPreferences();
  Future<void> setChatHistoryEnabled(bool enabled) =>
      _controller.setChatHistoryEnabled(connectionId, enabled);
  Future<void> setChatRetention(HistoryRetention retention) =>
      _controller.setChatRetention(connectionId, retention);
  Future<int> clearChatHistory() => _controller.clearChatHistory();
  Future<void> loadReconnectPreference() =>
      _controller.loadReconnectPreference();
  Future<bool> eraseIdentityAndSecrets() =>
      _controller.eraseIdentityAndSecrets();
}

/// Immutable snapshot of the last connect() arguments, replayed on reconnect.
class _ConnectRequest {
  final String address;
  final String nickname;
  final String? channel;
  final String? password;
  final String? channelPassword;

  const _ConnectRequest({
    required this.address,
    required this.nickname,
    this.channel,
    this.password,
    this.channelPassword,
  });
}

// ─── Server List Notifier ───────────────────────────────────────────

class ServerListNotifier extends Notifier<ServerListState> {
  @override
  ServerListState build() {
    _loadFromDisk();
    return const ServerListState();
  }

  /// Pinned servers first, then the saved order.
  List<Server> sortedServers() {
    final favs = state.favoriteIds;
    return [
      ...state.servers.where((s) => favs.contains(s.id)),
      ...state.servers.where((s) => !favs.contains(s.id)),
    ];
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('servers') ?? [];
    final servers = <Server>[];
    var migratedLegacyPassword = false;

    try {
      for (final encoded in data) {
        final json = jsonDecode(encoded) as Map<String, dynamic>;
        final bookmark = Server.fromJson(json);
        final serverSecretKey = SecureStorage.serverPasswordKey(bookmark.id);
        final channelSecretKey = SecureStorage.channelPasswordKey(bookmark.id);
        var password = await SecureStorage.get(serverSecretKey);
        var channelPassword = await SecureStorage.get(channelSecretKey);
        final legacyPassword = json['password'] as String?;
        final legacyChannelPassword = json['channel_password'] as String?;
        if (password == null && legacyPassword?.isNotEmpty == true) {
          await SecureStorage.put(serverSecretKey, legacyPassword!);
          password = legacyPassword;
          migratedLegacyPassword = true;
        }
        if (channelPassword == null &&
            legacyChannelPassword?.isNotEmpty == true) {
          await SecureStorage.put(channelSecretKey, legacyChannelPassword!);
          channelPassword = legacyChannelPassword;
          migratedLegacyPassword = true;
        }
        servers.add(
          Server(
            id: bookmark.id,
            name: bookmark.name,
            address: bookmark.address,
            nickname: bookmark.nickname,
            channel: bookmark.channel,
            password: password,
            channelPassword: channelPassword,
          ),
        );
      }
      state = state.copyWith(servers: servers, loading: false);
      // Restore pinned server ids so the home screen keeps them first.
      final favorites = prefs.getStringList('server_favorites') ?? const [];
      state = state.copyWith(favoriteIds: favorites.toSet());
      if (migratedLegacyPassword) {
        // Server.toJson deliberately omits passwords, so this removes every
        // migrated plaintext value from SharedPreferences.
        await _saveToDisk();
      }
    } catch (error) {
      AppLog.e(_tag, 'server secret migration failed', error);
      state = state.copyWith(servers: const [], loading: false);
    }
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('server_favorites', state.favoriteIds.toList());
  }

  /// Pins/unpins a server (pinned servers sort first on the home screen).
  Future<void> toggleFavorite(String serverId) async {
    final favs = Set<String>.from(state.favoriteIds);
    if (!favs.remove(serverId)) favs.add(serverId);
    state = state.copyWith(favoriteIds: favs);
    // Re-sort so a newly pinned server appears first immediately.
    state = state.copyWith(
      servers: sortServers(state.servers, state.favoriteIds),
    );
    await _saveFavorites();
    await _saveToDisk();
  }

  /// Moves a server one position up in the list (if it is not pinned first).
  Future<void> moveUp(String serverId) => _move(serverId, -1);

  /// Moves a server one position down in the list.
  Future<void> moveDown(String serverId) => _move(serverId, 1);

  Future<void> _move(String serverId, int delta) async {
    state = state.copyWith(
      servers: moveServer(state.servers, state.favoriteIds, serverId, delta),
    );
    await _saveToDisk();
  }

  Future<void> _saveToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'servers',
      state.servers.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }

  Future<void> _saveServerPasswords(Server server) async {
    final serverKey = SecureStorage.serverPasswordKey(server.id);
    final channelKey = SecureStorage.channelPasswordKey(server.id);
    if (server.password?.isNotEmpty == true) {
      await SecureStorage.put(serverKey, server.password!);
    } else {
      await SecureStorage.delete(serverKey);
    }
    if (server.channelPassword?.isNotEmpty == true) {
      await SecureStorage.put(channelKey, server.channelPassword!);
    } else {
      await SecureStorage.delete(channelKey);
    }
  }

  Future<void> addServer(Server server) async {
    await _saveServerPasswords(server);
    state = state.copyWith(servers: [...state.servers, server]);
    await _saveToDisk();
  }

  Future<void> updateServer(Server server) async {
    final idx = state.servers.indexWhere((s) => s.id == server.id);
    if (idx < 0) return;
    await _saveServerPasswords(server);
    final updated = [...state.servers];
    updated[idx] = server;
    state = state.copyWith(servers: updated);
    await _saveToDisk();
  }

  Future<int> eraseAllSecrets() async {
    var erased = 0;
    for (final server in state.servers) {
      for (final key in [
        SecureStorage.serverPasswordKey(server.id),
        SecureStorage.channelPasswordKey(server.id),
      ]) {
        try {
          await SecureStorage.delete(key);
          erased++;
        } catch (error) {
          AppLog.d(_tag, 'secret delete skipped (${error.runtimeType})');
        }
      }
    }
    state = state.copyWith(
      servers: state.servers
          .map(
            (s) => s.copyWith(clearPassword: true, clearChannelPassword: true),
          )
          .toList(),
    );
    return erased;
  }

  Future<void> removeServer(String serverId) async {
    await SecureStorage.delete(SecureStorage.serverPasswordKey(serverId));
    await SecureStorage.delete(SecureStorage.channelPasswordKey(serverId));
    state = state.copyWith(
      servers: state.servers.where((s) => s.id != serverId).toList(),
    );
    await _saveToDisk();
  }
}

// ─── Providers ──────────────────────────────────────────────────────

final tsMultiServerProvider =
    NotifierProvider<MultiServerNotifier, MultiServerState>(
      MultiServerNotifier.new,
    );

/// Per-session state + actions, keyed by the engine's connection id.
final tsSessionProvider = Provider.family<TsSessionView, int>((ref, cid) {
  final multi = ref.watch(tsMultiServerProvider);
  final notifier = ref.read(tsMultiServerProvider.notifier);
  return TsSessionView(
    state: multi.sessions[cid] ?? TsConnectionState(connectionId: cid),
    actions: TsConnectionNotifier(notifier, cid),
  );
});

/// The currently focused session (state + actions). Kept for widgets that
/// render "the one visible server".
final tsSelectedProvider = Provider<TsSessionView>((ref) {
  final multi = ref.watch(tsMultiServerProvider);
  final notifier = ref.read(tsMultiServerProvider.notifier);
  final cid = multi.selectedId;
  if (cid == null) {
    return TsSessionView(
      state: const TsConnectionState(),
      actions: TsConnectionNotifier(notifier, 0),
    );
  }
  return ref.watch(tsSessionProvider(cid));
});

final serverListProvider =
    NotifierProvider<ServerListNotifier, ServerListState>(
      ServerListNotifier.new,
    );

// ─── Master volume (app-wide output gain) ───────────────────────────

class MasterVolumeState {
  final double volumeDb;
  const MasterVolumeState({this.volumeDb = 0.0});
  MasterVolumeState copyWith({double? volumeDb}) =>
      MasterVolumeState(volumeDb: volumeDb ?? this.volumeDb);
}

class MasterVolumeNotifier extends Notifier<MasterVolumeState> {
  static const _prefKey = 'master_volume_db';

  @override
  MasterVolumeState build() {
    // Load the persisted value after the first frame (default 0 dB).
    Future<void>.microtask(_restore);
    return const MasterVolumeState();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_prefKey)) return;
    final db = prefs.getDouble(_prefKey) ?? 0.0;
    if (db != state.volumeDb) {
      state = state.copyWith(volumeDb: db);
      TsNative.setMasterVolume(db);
    }
  }

  Future<void> setVolume(double volumeDb) async {
    final db = volumeDb.clamp(-20.0, 20.0);
    state = state.copyWith(volumeDb: db);
    TsNative.setMasterVolume(db);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKey, db);
  }

  /// Applies a volume to the engine and in-memory state WITHOUT persisting it.
  ///
  /// Used by the temporary focus duck/unduck: a transient phone call must lower
  /// the output for the duration of the call and restore it afterwards, but it
  /// must not overwrite the value the user chose in settings with the ducked
  /// value that happens to be live at that moment.
  void setVolumeLive(double volumeDb) {
    final db = volumeDb.clamp(-20.0, 20.0);
    state = state.copyWith(volumeDb: db);
    TsNative.setMasterVolume(db);
  }
}

final masterVolumeProvider =
    NotifierProvider<MasterVolumeNotifier, MasterVolumeState>(
      MasterVolumeNotifier.new,
    );

// ─── Contact settings (per server + user UID) ───────────────────────

/// Loads the contact settings for one server+UID, or a default when none was
/// saved. Exposed as a family so the client detail and the client list can both
/// read/write a user's per-contact name, mute and ignore flags.
/// [ContactStore.save] writes to SharedPreferences; the provider is invalidated
/// after a write so the UI reflects the new value immediately.
final contactProvider =
    FutureProvider.family<ContactSettings, ({String serverUid, String uid})>((
      ref,
      key,
    ) async {
      final existing = await ContactStore.load(key.serverUid, key.uid);
      return existing ??
          ContactSettings(serverUid: key.serverUid, uid: key.uid);
    });

/// Writes a contact setting and refreshes the provider. Accepts the
/// [WidgetRef] you get from a `Consumer` builder (Riverpod 2).
Future<void> saveContact(ContactSettings c, WidgetRef ref) async {
  await ContactStore.save(c);
  ref.invalidate(contactProvider((serverUid: c.serverUid, uid: c.uid)));
}

/// The last successful connection, kept across process death so the home
/// screen can offer a one-tap resume (C5).
final resumeIntentProvider = FutureProvider<ResumeIntent?>(
  (ref) => ResumeIntentStore.load(),
);
