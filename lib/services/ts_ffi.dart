import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

import 'app_log.dart';

// Load the native Rust library
final DynamicLibrary _lib = _loadLib();

DynamicLibrary _loadLib() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libtsclient.so');
  }
  throw UnsupportedError('Platform not supported');
}

// ─── C function typedefs ────────────────────────────────────────────
//
// Every session-scoped function takes the `connection_id` (u64) as its FIRST
// argument. Engine-wide functions (identity, log level, event notifier) do
// not.

// ts_connect(address, nickname, channel, server_password, channel_password)
// -> *char (JSON) carrying the new `connection_id`
typedef _ConnectNative =
    Pointer<Utf8> Function(
      Pointer<Utf8> address,
      Pointer<Utf8> nickname,
      Pointer<Utf8> channel,
      Pointer<Utf8> password,
      Pointer<Utf8> channelPassword,
    );
typedef _ConnectDart =
    Pointer<Utf8> Function(
      Pointer<Utf8> address,
      Pointer<Utf8> nickname,
      Pointer<Utf8> channel,
      Pointer<Utf8> password,
      Pointer<Utf8> channelPassword,
    );

// ts_disconnect(connection_id) -> *char (JSON)
typedef _DisconnectNative = Pointer<Utf8> Function(Uint64);
typedef _DisconnectDart = Pointer<Utf8> Function(int);

// Edge-triggered wake-up callback. Event payloads remain in Rust and are
// drained with ts_poll_events().
typedef _EventNotifierNative = Void Function();
typedef _SetEventNotifierNative =
    Void Function(Pointer<NativeFunction<_EventNotifierNative>> callback);
typedef _SetEventNotifierDart =
    void Function(Pointer<NativeFunction<_EventNotifierNative>> callback);

// ts_cancel_connect(connection_id) -> bool
typedef _CancelConnectNative = Uint8 Function(Uint64);
typedef _CancelConnectDart = int Function(int);

// ts_poll_events() -> *char (JSON array of {connection_id, ...event})
typedef _PollEventsNative = Pointer<Utf8> Function();
typedef _PollEventsDart = Pointer<Utf8> Function();

// ts_get_channels(connection_id) -> *char (JSON array)
typedef _GetChannelsNative = Pointer<Utf8> Function(Uint64);
typedef _GetChannelsDart = Pointer<Utf8> Function(int);

// ts_get_clients(connection_id) -> *char (JSON array)
typedef _GetClientsNative = Pointer<Utf8> Function(Uint64);
typedef _GetClientsDart = Pointer<Utf8> Function(int);

// ts_send_channel_message(connection_id, channel_id, message) -> bool
typedef _SendChannelMsgNative = Uint8 Function(Uint64, Uint32, Pointer<Utf8>);
typedef _SendChannelMsgDart = int Function(int, int, Pointer<Utf8>);

// ts_send_private_message(connection_id, client_id, message) -> bool
typedef _SendPrivateMsgNative = Uint8 Function(Uint64, Uint32, Pointer<Utf8>);
typedef _SendPrivateMsgDart = int Function(int, int, Pointer<Utf8>);

// ts_send_server_message(connection_id, message) -> bool
typedef _SendServerMsgNative = Uint8 Function(Uint64, Pointer<Utf8>);
typedef _SendServerMsgDart = int Function(int, Pointer<Utf8>);

// ts_move_to_channel(connection_id, channel_id, password) -> bool
typedef _MoveToChannelNative =
    Uint8 Function(Uint64, Uint32, Pointer<Utf8> password);
typedef _MoveToChannelDart = int Function(int, int, Pointer<Utf8> password);

// ts_set_muted(connection_id, input_muted, output_muted) -> bool
typedef _SetMutedNative = Uint8 Function(Uint64, Uint8, Uint8);
typedef _SetMutedDart = int Function(int, int, int);

// ts_is_connected(connection_id) -> bool
typedef _IsConnectedNative = Uint8 Function(Uint64);
typedef _IsConnectedDart = int Function(int);

// ts_set_vad_threshold(connection_id, threshold: f32)
typedef _SetVadThresholdNative = Void Function(Uint64, Float);
typedef _SetVadThresholdDart = void Function(int, double);

// ts_set_vad_enabled(connection_id, enabled: bool) -> bool
typedef _SetVadEnabledNative = Uint8 Function(Uint64, Uint8);
typedef _SetVadEnabledDart = int Function(int, int);

// ts_is_voice_active(connection_id) -> bool
typedef _IsVoiceActiveNative = Uint8 Function(Uint64);
typedef _IsVoiceActiveDart = int Function(int);

// ts_start_audio(connection_id) -> bool
typedef _StartAudioNative = Uint8 Function(Uint64);
typedef _StartAudioDart = int Function(int);

// ts_stop_audio(connection_id)
typedef _StopAudioNative = Void Function(Uint64);
typedef _StopAudioDart = void Function(int);

// ts_send_audio(connection_id, data: *const f32, data_len: u32) -> bool
typedef _SendAudioNative = Uint8 Function(Uint64, Pointer<Float>, Uint32);
typedef _SendAudioDart = int Function(int, Pointer<Float>, int);

// ts_set_identity(json: *const c_char)
typedef _SetIdentityNative = Void Function(Pointer<Utf8>);
typedef _SetIdentityDart = void Function(Pointer<Utf8>);

// ts_get_identity() -> *mut c_char (null if none set)
typedef _GetIdentityNative = Pointer<Utf8> Function();
typedef _GetIdentityDart = Pointer<Utf8> Function();

// ts_clear_identity() -> bool
typedef _ClearIdentityNative = Uint8 Function();
typedef _ClearIdentityDart = int Function();

// ts_set_log_level(level: u8) -> bool
typedef _SetLogLevelNative = Uint8 Function(Uint8);
typedef _SetLogLevelDart = int Function(int);

// ts_download_file(connection_id, channel_id, remote_path, channel_password,
//                  target, max) -> u32
typedef _DownloadFileNative =
    Uint32 Function(
      Uint64,
      Uint64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Uint64,
    );
typedef _DownloadFileDart =
    int Function(int, int, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);

// ts_cancel_file_transfer(connection_id, id) -> bool
typedef _CancelTransferNative = Uint8 Function(Uint64, Uint32);
typedef _CancelTransferDart = int Function(int, int);

// ts_kick_client(connection_id, client_id, from_server, reason) -> bool
typedef _KickClientNative =
    Uint8 Function(Uint64, Uint16, Uint8, Pointer<Utf8>);
typedef _KickClientDart = int Function(int, int, int, Pointer<Utf8>);

// ts_ban_client(connection_id, client_id, seconds, reason) -> bool
typedef _BanClientNative =
    Uint8 Function(Uint64, Uint16, Uint64, Pointer<Utf8>);
typedef _BanClientDart = int Function(int, int, int, Pointer<Utf8>);

// ts_poke_client(connection_id, client_id, message) -> bool
typedef _PokeClientNative = Uint8 Function(Uint64, Uint16, Pointer<Utf8>);
typedef _PokeClientDart = int Function(int, int, Pointer<Utf8>);

// ts_move_client(connection_id, client_id, channel_id, password) -> bool
typedef _MoveClientNative =
    Uint8 Function(Uint64, Uint16, Uint64, Pointer<Utf8>);
typedef _MoveClientDart = int Function(int, int, int, Pointer<Utf8>);

// ts_set_away(connection_id, away, message) -> bool
typedef _SetAwayNative = Uint8 Function(Uint64, Uint8, Pointer<Utf8>);
typedef _SetAwayDart = int Function(int, int, Pointer<Utf8>);

// ts_set_nickname(connection_id, name) -> bool
typedef _SetNicknameNative = Uint8 Function(Uint64, Pointer<Utf8>);
typedef _SetNicknameDart = int Function(int, Pointer<Utf8>);

// ts_set_channel_commander(connection_id, enabled) -> bool
typedef _SetCommanderNative = Uint8 Function(Uint64, Uint8);
typedef _SetCommanderDart = int Function(int, int);

// ts_set_mic_gain(connection_id, gain: f32)
typedef _SetMicGainNative = Void Function(Uint64, Float);
typedef _SetMicGainDart = void Function(int, double);

// ts_set_client_volume(connection_id, client_id: u16, volume_db: f32)
typedef _SetClientVolumeNative = Void Function(Uint64, Uint16, Float);
typedef _SetClientVolumeDart = void Function(int, int, double);

// ts_set_master_volume(volume_db: f32)
typedef _SetMasterVolumeNative = Void Function(Float);
typedef _SetMasterVolumeDart = void Function(double);

// ts_set_whisper_targets(connection_id, json) -> bool
typedef _SetWhisperTargetsNative = Uint8 Function(Uint64, Pointer<Utf8>);
typedef _SetWhisperTargetsDart = int Function(int, Pointer<Utf8>);

// ts_set_whisper_active(connection_id, active) -> bool
typedef _SetWhisperActiveNative = Uint8 Function(Uint64, Uint8);
typedef _SetWhisperActiveDart = int Function(int, int);

// ts_set_whisper_allow_mode(connection_id, mode) -> bool
typedef _SetWhisperAllowModeNative = Uint8 Function(Uint64, Uint8);
typedef _SetWhisperAllowModeDart = int Function(int, int);

// ts_set_whisper_allowlist(connection_id, json array of UIDs) -> bool
typedef _SetWhisperAllowlistNative = Uint8 Function(Uint64, Pointer<Utf8>);
typedef _SetWhisperAllowlistDart = int Function(int, Pointer<Utf8>);

// ts_get_whisper_status(connection_id) -> *char (JSON)
typedef _GetWhisperStatusNative = Pointer<Utf8> Function(Uint64);
typedef _GetWhisperStatusDart = Pointer<Utf8> Function(int);

// ts_upload_file(connection_id, channel_id, remote_path, channel_password,
//                source_path, overwrite) -> u32
typedef _UploadFileNative =
    Uint32 Function(
      Uint64,
      Uint64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Uint8,
    );
typedef _UploadFileDart =
    int Function(int, int, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);

// ts_list_files(connection_id, channel_id, path, channel_password) -> u32
typedef _ListFilesNative =
    Uint32 Function(Uint64, Uint64, Pointer<Utf8>, Pointer<Utf8>);
typedef _ListFilesDart = int Function(int, int, Pointer<Utf8>, Pointer<Utf8>);

// ts_delete_file(connection_id, channel_id, path, channel_password) -> bool
typedef _DeleteFileNative =
    Uint8 Function(Uint64, Uint64, Pointer<Utf8>, Pointer<Utf8>);
typedef _DeleteFileDart = int Function(int, int, Pointer<Utf8>, Pointer<Utf8>);

// ts_create_directory(connection_id, channel_id, path, channel_password) -> bool
typedef _CreateDirNative =
    Uint8 Function(Uint64, Uint64, Pointer<Utf8>, Pointer<Utf8>);
typedef _CreateDirDart = int Function(int, int, Pointer<Utf8>, Pointer<Utf8>);

// ts_rename_file(connection_id, channel_id, old_name, new_name, channel_password,
//                target_channel_id, target_channel_password) -> bool
typedef _RenameFileNative =
    Uint8 Function(
      Uint64,
      Uint64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Uint64,
      Pointer<Utf8>,
    );
typedef _RenameFileDart =
    int Function(
      int,
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
      Pointer<Utf8>,
    );

// ts_file_info(connection_id, channel_id, name, channel_password) -> u32
typedef _FileInfoNative =
    Uint32 Function(Uint64, Uint64, Pointer<Utf8>, Pointer<Utf8>);
typedef _FileInfoDart = int Function(int, int, Pointer<Utf8>, Pointer<Utf8>);

// ts_use_token(connection_id, token) -> bool
typedef _UseTokenNative = Uint8 Function(Uint64, Pointer<Utf8>);
typedef _UseTokenDart = int Function(int, Pointer<Utf8>);

// ts_create_channel(connection_id, parent_id, name, topic, description,
//                   password, max_clients, permanent, semi_permanent) -> bool
typedef _CreateChannelNative =
    Uint8 Function(
      Uint64,
      Uint64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int32,
      Uint8,
      Uint8,
    );
typedef _CreateChannelDart =
    int Function(
      int,
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
      int,
      int,
    );

// ts_edit_channel(connection_id, channel_id, name, topic, description,
//                 password, has_password, max_clients, permanent, semi_permanent)
// -> bool
typedef _EditChannelNative =
    Uint8 Function(
      Uint64,
      Uint64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int32,
      Int32,
      Int32,
      Int32,
    );
typedef _EditChannelDart =
    int Function(
      int,
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
      int,
      int,
      int,
    );

// ts_delete_channel(connection_id, channel_id, force) -> bool
typedef _DeleteChannelNative = Uint8 Function(Uint64, Uint64, Uint8);
typedef _DeleteChannelDart = int Function(int, int, int);

// ts_move_channel_tree(connection_id, channel_id, parent_id, order) -> bool
typedef _MoveChannelTreeNative = Uint8 Function(Uint64, Uint64, Uint64, Uint64);
typedef _MoveChannelTreeDart = int Function(int, int, int, int);

// ─── Bindings ───────────────────────────────────────────────────────

final _connect = _lib.lookupFunction<_ConnectNative, _ConnectDart>(
  'ts_connect',
);
final _disconnect = _lib.lookupFunction<_DisconnectNative, _DisconnectDart>(
  'ts_disconnect',
);
final _setEventNotifier = _lib
    .lookupFunction<_SetEventNotifierNative, _SetEventNotifierDart>(
      'ts_set_event_notifier',
    );
final _cancelConnect = _lib
    .lookupFunction<_CancelConnectNative, _CancelConnectDart>(
      'ts_cancel_connect',
    );
final _pollEvents = _lib.lookupFunction<_PollEventsNative, _PollEventsDart>(
  'ts_poll_events',
);
final _getChannels = _lib.lookupFunction<_GetChannelsNative, _GetChannelsDart>(
  'ts_get_channels',
);
final _getClients = _lib.lookupFunction<_GetClientsNative, _GetClientsDart>(
  'ts_get_clients',
);
final _sendChannelMsg = _lib
    .lookupFunction<_SendChannelMsgNative, _SendChannelMsgDart>(
      'ts_send_channel_message',
    );
final _sendPrivateMsg = _lib
    .lookupFunction<_SendPrivateMsgNative, _SendPrivateMsgDart>(
      'ts_send_private_message',
    );
final _sendServerMsg = _lib
    .lookupFunction<_SendServerMsgNative, _SendServerMsgDart>(
      'ts_send_server_message',
    );
final _moveToChannel = _lib
    .lookupFunction<_MoveToChannelNative, _MoveToChannelDart>(
      'ts_move_to_channel',
    );
final _setMuted = _lib.lookupFunction<_SetMutedNative, _SetMutedDart>(
  'ts_set_muted',
);
final _isConnected = _lib.lookupFunction<_IsConnectedNative, _IsConnectedDart>(
  'ts_is_connected',
);
final _setVadThreshold = _lib
    .lookupFunction<_SetVadThresholdNative, _SetVadThresholdDart>(
      'ts_set_vad_threshold',
    );
final _setVadEnabled = _lib
    .lookupFunction<_SetVadEnabledNative, _SetVadEnabledDart>(
      'ts_set_vad_enabled',
    );
final _isVoiceActive = _lib
    .lookupFunction<_IsVoiceActiveNative, _IsVoiceActiveDart>(
      'ts_is_voice_active',
    );
final _startAudio = _lib.lookupFunction<_StartAudioNative, _StartAudioDart>(
  'ts_start_audio',
);
final _stopAudio = _lib.lookupFunction<_StopAudioNative, _StopAudioDart>(
  'ts_stop_audio',
);
final _sendAudio = _lib.lookupFunction<_SendAudioNative, _SendAudioDart>(
  'ts_send_audio',
);
final _setIdentity = _lib.lookupFunction<_SetIdentityNative, _SetIdentityDart>(
  'ts_set_identity',
);
final _getIdentity = _lib.lookupFunction<_GetIdentityNative, _GetIdentityDart>(
  'ts_get_identity',
);
final _clearIdentity = _lib
    .lookupFunction<_ClearIdentityNative, _ClearIdentityDart>(
      'ts_clear_identity',
    );
final _setLogLevel = _lib.lookupFunction<_SetLogLevelNative, _SetLogLevelDart>(
  'ts_set_log_level',
);
final _downloadFile = _lib
    .lookupFunction<_DownloadFileNative, _DownloadFileDart>('ts_download_file');
final _cancelTransfer = _lib
    .lookupFunction<_CancelTransferNative, _CancelTransferDart>(
      'ts_cancel_file_transfer',
    );
final _kickClient = _lib.lookupFunction<_KickClientNative, _KickClientDart>(
  'ts_kick_client',
);
final _banClient = _lib.lookupFunction<_BanClientNative, _BanClientDart>(
  'ts_ban_client',
);
final _pokeClient = _lib.lookupFunction<_PokeClientNative, _PokeClientDart>(
  'ts_poke_client',
);
final _moveClient = _lib.lookupFunction<_MoveClientNative, _MoveClientDart>(
  'ts_move_client',
);
final _setAway = _lib.lookupFunction<_SetAwayNative, _SetAwayDart>(
  'ts_set_away',
);
final _setNickname = _lib.lookupFunction<_SetNicknameNative, _SetNicknameDart>(
  'ts_set_nickname',
);
final _setChannelCommander = _lib
    .lookupFunction<_SetCommanderNative, _SetCommanderDart>(
      'ts_set_channel_commander',
    );
final _setMicGain = _lib.lookupFunction<_SetMicGainNative, _SetMicGainDart>(
  'ts_set_mic_gain',
);
final _setClientVolume = _lib
    .lookupFunction<_SetClientVolumeNative, _SetClientVolumeDart>(
      'ts_set_client_volume',
    );
final _setMasterVolume = _lib
    .lookupFunction<_SetMasterVolumeNative, _SetMasterVolumeDart>(
      'ts_set_master_volume',
    );
final _setWhisperTargets = _lib
    .lookupFunction<_SetWhisperTargetsNative, _SetWhisperTargetsDart>(
      'ts_set_whisper_targets',
    );
final _setWhisperActive = _lib
    .lookupFunction<_SetWhisperActiveNative, _SetWhisperActiveDart>(
      'ts_set_whisper_active',
    );
final _setWhisperAllowMode = _lib
    .lookupFunction<_SetWhisperAllowModeNative, _SetWhisperAllowModeDart>(
      'ts_set_whisper_allow_mode',
    );
final _setWhisperAllowlist = _lib
    .lookupFunction<_SetWhisperAllowlistNative, _SetWhisperAllowlistDart>(
      'ts_set_whisper_allowlist',
    );
final _getWhisperStatus = _lib
    .lookupFunction<_GetWhisperStatusNative, _GetWhisperStatusDart>(
      'ts_get_whisper_status',
    );
final _uploadFile = _lib.lookupFunction<_UploadFileNative, _UploadFileDart>(
  'ts_upload_file',
);
final _listFiles = _lib.lookupFunction<_ListFilesNative, _ListFilesDart>(
  'ts_list_files',
);
final _deleteFile = _lib.lookupFunction<_DeleteFileNative, _DeleteFileDart>(
  'ts_delete_file',
);
final _createDir = _lib.lookupFunction<_CreateDirNative, _CreateDirDart>(
  'ts_create_directory',
);
final _renameFile = _lib.lookupFunction<_RenameFileNative, _RenameFileDart>(
  'ts_rename_file',
);
final _fileInfo = _lib.lookupFunction<_FileInfoNative, _FileInfoDart>(
  'ts_file_info',
);
final _useToken = _lib.lookupFunction<_UseTokenNative, _UseTokenDart>(
  'ts_use_token',
);
final _createChannel = _lib
    .lookupFunction<_CreateChannelNative, _CreateChannelDart>(
      'ts_create_channel',
    );
final _editChannel = _lib.lookupFunction<_EditChannelNative, _EditChannelDart>(
  'ts_edit_channel',
);
final _deleteChannel = _lib
    .lookupFunction<_DeleteChannelNative, _DeleteChannelDart>(
      'ts_delete_channel',
    );
final _moveChannelTree = _lib
    .lookupFunction<_MoveChannelTreeNative, _MoveChannelTreeDart>(
      'ts_move_channel_tree',
    );

// ─── Helper ─────────────────────────────────────────────────────────

String _ptrToString(Pointer<Utf8> ptr) {
  if (ptr == nullptr) {
    throw StateError('Native TeamSpeak engine returned a null string pointer');
  }
  try {
    return ptr.toDartString();
  } finally {
    // Use Rust's ts_free_string to free CString memory properly.
    _freeString(ptr.cast());
  }
}

// ts_free_string frees memory allocated by Rust's CString::into_raw()
typedef _FreeStringNative = Void Function(Pointer<Void>);
typedef _FreeStringDart = void Function(Pointer<Void>);
final _freeString = _lib.lookupFunction<_FreeStringNative, _FreeStringDart>(
  'ts_free_string',
);

Pointer<Utf8> _strToPtr(String? s) {
  if (s == null) return nullptr;
  return s.toNativeUtf8();
}

void _freeInputString(Pointer<Utf8> ptr) {
  if (ptr != nullptr) malloc.free(ptr);
}

// ─── Public API ─────────────────────────────────────────────────────

/// One event drained from the shared Rust queue, tagged with the session
/// (`connectionId`) it belongs to. `connectionId == 0` is an engine-wide
/// diagnostic.
class TsEngineEvent {
  final int connectionId;
  final Map<String, dynamic> data;

  const TsEngineEvent({required this.connectionId, required this.data});

  String get type => data['type'] as String? ?? '';
}

class TsNative {
  static NativeCallable<Void Function()>? _eventNotifier;
  static void Function()? onEventsAvailable;

  /// Register one process-lifetime native wake-up callback. Native worker
  /// threads may invoke it safely; NativeCallable.listener posts back to the
  /// creating Dart isolate without executing Dart on the Rust thread.
  static void initializeEventNotifier() {
    if (_eventNotifier != null) return;
    _eventNotifier = NativeCallable<Void Function()>.listener(() {
      onEventsAvailable?.call();
    });
    _setEventNotifier(_eventNotifier!.nativeFunction);
  }

  /// Starts a connection attempt and returns the JSON result from the engine.
  /// On success the payload carries the newly allocated `connection_id` that
  /// every subsequent session-scoped call must use.
  static String connect(
    String address,
    String nickname, {
    String? channel,
    String? password,
    String? channelPassword,
  }) {
    debugLog('connect($address, $nickname, ch=$channel)');
    final addressPtr = _strToPtr(address);
    final nicknamePtr = _strToPtr(nickname);
    final channelPtr = _strToPtr(channel);
    final passwordPtr = _strToPtr(password);
    final channelPasswordPtr = _strToPtr(channelPassword);
    try {
      final result = _connect(
        addressPtr,
        nicknamePtr,
        channelPtr,
        passwordPtr,
        channelPasswordPtr,
      );
      final str = _ptrToString(result);
      debugLog('connect -> $str');
      return str;
    } finally {
      // Native code reads these values synchronously before spawning its
      // connection task, so ownership stays with Dart and must be released.
      _freeInputString(addressPtr);
      _freeInputString(nicknamePtr);
      _freeInputString(channelPtr);
      _freeInputString(passwordPtr);
      _freeInputString(channelPasswordPtr);
    }
  }

  /// Aborts an in-flight connection attempt. Returns false when there was
  /// nothing to cancel.
  static bool cancelConnect(int connectionId) {
    debugLog('cancelConnect($connectionId)');
    return _cancelConnect(connectionId) != 0;
  }

  static String disconnect(int connectionId) {
    debugLog('disconnect($connectionId)');
    final result = _ptrToString(_disconnect(connectionId));
    debugLog('disconnect -> $result');
    return result;
  }

  /// Drains the global event queue, each entry tagged with its connection id.
  static List<TsEngineEvent> pollEvents() {
    final result = _ptrToString(_pollEvents());
    final decoded = jsonDecode(result) as List;
    return decoded.map((raw) {
      final map = raw as Map<String, dynamic>;
      return TsEngineEvent(
        connectionId: (map['connection_id'] as num?)?.toInt() ?? 0,
        data: Map<String, dynamic>.from(map),
      );
    }).toList();
  }

  static String getChannels(int connectionId) {
    return _ptrToString(_getChannels(connectionId));
  }

  static String getClients(int connectionId) {
    return _ptrToString(_getClients(connectionId));
  }

  static bool sendChannelMessage(
    int connectionId,
    int channelId,
    String message,
  ) {
    debugLog('sendChannelMessage(cid=$channelId, len=${message.length})');
    final messagePtr = _strToPtr(message);
    try {
      final result = _sendChannelMsg(connectionId, channelId, messagePtr);
      debugLog('sendChannelMessage -> $result');
      return result != 0;
    } finally {
      _freeInputString(messagePtr);
    }
  }

  static bool sendPrivateMessage(
    int connectionId,
    int clientId,
    String message,
  ) {
    debugLog('sendPrivateMessage(client=$clientId, len=${message.length})');
    final messagePtr = _strToPtr(message);
    try {
      return _sendPrivateMsg(connectionId, clientId, messagePtr) != 0;
    } finally {
      _freeInputString(messagePtr);
    }
  }

  static bool sendServerMessage(int connectionId, String message) {
    debugLog('sendServerMessage(len=${message.length})');
    final messagePtr = _strToPtr(message);
    try {
      return _sendServerMsg(connectionId, messagePtr) != 0;
    } finally {
      _freeInputString(messagePtr);
    }
  }

  static bool moveToChannel(
    int connectionId,
    int channelId, {
    String? password,
  }) {
    debugLog('moveToChannel($channelId, protected=${password != null})');
    final passwordPtr = _strToPtr(password);
    try {
      final result = _moveToChannel(connectionId, channelId, passwordPtr) != 0;
      debugLog('moveToChannel -> $result');
      return result;
    } finally {
      _freeInputString(passwordPtr);
    }
  }

  static bool setMuted({
    required int connectionId,
    required bool input,
    required bool output,
  }) {
    debugLog('setMuted(inp=$input, out=$output)');
    final result = _setMuted(connectionId, input ? 1 : 0, output ? 1 : 0) != 0;
    debugLog('setMuted -> $result');
    return result;
  }

  static bool isConnected(int connectionId) {
    return _isConnected(connectionId) != 0;
  }

  static void setIdentity(String json) {
    final ptr = _strToPtr(json);
    _setIdentity(ptr);
    malloc.free(ptr);
  }

  static String? getIdentity() {
    final ptr = _getIdentity();
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      _freeString(ptr.cast());
    }
  }

  static bool clearIdentity() {
    debugLog('clearIdentity()');
    return _clearIdentity() != 0;
  }

  /// Mirrors the Dart log level onto the engine: 0 off … 4 debug.
  static bool setLogLevel(int level) {
    return _setLogLevel(level) != 0;
  }

  /// Starts a file download. Returns the transfer id, or 0 when the engine
  /// refused the request (bad path, size out of range, not connected).
  static int downloadFile({
    required int connectionId,
    required int channelId,
    required String remotePath,
    required String targetPath,
    required int maxBytes,
    String? channelPassword,
  }) {
    final remotePtr = _strToPtr(remotePath);
    final targetPtr = _strToPtr(targetPath);
    final passwordPtr = _strToPtr(channelPassword);
    try {
      return _downloadFile(
        connectionId,
        channelId,
        remotePtr,
        passwordPtr,
        targetPtr,
        maxBytes,
      );
    } finally {
      _freeInputString(remotePtr);
      _freeInputString(targetPtr);
      _freeInputString(passwordPtr);
    }
  }

  static bool cancelFileTransfer(int connectionId, int transferId) {
    return _cancelTransfer(connectionId, transferId) != 0;
  }

  /// Kicks a client from its channel, or from the server when
  /// [fromServer] is true. The server enforces the permission.
  static bool kickClient(
    int connectionId,
    int clientId, {
    required bool fromServer,
    String? reason,
  }) {
    debugLog('kickClient(fromServer=$fromServer)');
    final ptr = _strToPtr(reason);
    try {
      return _kickClient(connectionId, clientId, fromServer ? 1 : 0, ptr) != 0;
    } finally {
      _freeInputString(ptr);
    }
  }

  /// Bans a client for [seconds] (0 = permanent).
  static bool banClient(
    int connectionId,
    int clientId, {
    int seconds = 0,
    String? reason,
  }) {
    debugLog('banClient(seconds=$seconds)');
    final ptr = _strToPtr(reason);
    try {
      return _banClient(connectionId, clientId, seconds, ptr) != 0;
    } finally {
      _freeInputString(ptr);
    }
  }

  static bool pokeClient(int connectionId, int clientId, String message) {
    debugLog('pokeClient(len=${message.length})');
    final ptr = _strToPtr(message);
    try {
      return _pokeClient(connectionId, clientId, ptr) != 0;
    } finally {
      _freeInputString(ptr);
    }
  }

  /// Moves another client to a channel.
  static bool moveClient(
    int connectionId,
    int clientId,
    int channelId, {
    String? password,
  }) {
    debugLog('moveClient(channel=$channelId)');
    final ptr = _strToPtr(password);
    try {
      return _moveClient(connectionId, clientId, channelId, ptr) != 0;
    } finally {
      _freeInputString(ptr);
    }
  }

  /// Away/AFK flag with an optional reason. Clearing it also clears the
  /// message on the server side.
  static bool setAway(int connectionId, bool away, {String? message}) {
    debugLog('setAway($away, hasMessage=${message != null})');
    final ptr = _strToPtr(message);
    try {
      return _setAway(connectionId, away ? 1 : 0, ptr) != 0;
    } finally {
      _freeInputString(ptr);
    }
  }

  /// In-session rename. Returns false when the engine rejected the name
  /// locally (3-30 characters); the server can still refuse it afterwards.
  static bool setNickname(int connectionId, String name) {
    debugLog('setNickname(len=${name.length})');
    final ptr = _strToPtr(name);
    try {
      return _setNickname(connectionId, ptr) != 0;
    } finally {
      _freeInputString(ptr);
    }
  }

  static bool setChannelCommander(int connectionId, bool enabled) {
    debugLog('setChannelCommander($enabled)');
    return _setChannelCommander(connectionId, enabled ? 1 : 0) != 0;
  }

  static void setVadThreshold(int connectionId, double threshold) {
    _setVadThreshold(connectionId, threshold);
  }

  static bool setVadEnabled(int connectionId, bool enabled) {
    return _setVadEnabled(connectionId, enabled ? 1 : 0) != 0;
  }

  static bool isVoiceActive(int connectionId) {
    return _isVoiceActive(connectionId) != 0;
  }

  static bool startAudio(int connectionId) {
    debugLog('startAudio($connectionId)');
    return _startAudio(connectionId) != 0;
  }

  static void stopAudio(int connectionId) {
    debugLog('stopAudio($connectionId)');
    _stopAudio(connectionId);
  }

  static bool sendAudio(int connectionId, Pointer<Float> data, int dataLen) {
    return _sendAudio(connectionId, data, dataLen) != 0;
  }

  static void setMicGain(int connectionId, double gain) {
    debugLog('setMicGain($gain)');
    _setMicGain(connectionId, gain);
  }

  static void setClientVolume(int connectionId, int clientId, double volumeDb) {
    _setClientVolume(connectionId, clientId, volumeDb);
  }

  /// App-wide output volume (dB, -20..+20), shared by every server.
  static void setMasterVolume(double volumeDb) {
    _setMasterVolume(volumeDb);
  }

  /// Replace the outgoing whisper target list. Native side sorts, de-dupes,
  /// drops the own client ID and caps each list at 100 entries.
  static bool setWhisperTargets({
    required int connectionId,
    required List<int> clientIds,
    required List<int> channelIds,
  }) {
    debugLog(
      'setWhisperTargets(clients=${clientIds.length}, '
      'channels=${channelIds.length})',
    );
    final payload = jsonEncode({'clients': clientIds, 'channels': channelIds});
    final ptr = _strToPtr(payload);
    try {
      return _setWhisperTargets(connectionId, ptr) != 0;
    } finally {
      _freeInputString(ptr);
    }
  }

  /// Arm/disarm whisper transmission. Returns false when no target is set.
  static bool setWhisperActive(int connectionId, bool active) {
    debugLog('setWhisperActive($active)');
    return _setWhisperActive(connectionId, active ? 1 : 0) != 0;
  }

  /// When enabled, incoming whispers are only played for allow-listed UIDs.
  static bool setWhisperAllowlistEnabled(int connectionId, bool enabled) {
    return _setWhisperAllowMode(connectionId, enabled ? 1 : 0) != 0;
  }

  /// Replace the incoming whisper allow list (client UIDs).
  static bool setWhisperAllowlist(int connectionId, List<String> uids) {
    final ptr = _strToPtr(jsonEncode(uids));
    try {
      return _setWhisperAllowlist(connectionId, ptr) != 0;
    } finally {
      _freeInputString(ptr);
    }
  }

  /// Whisper configuration as reported by the engine (JSON).
  static String getWhisperStatus(int connectionId) {
    return _ptrToString(_getWhisperStatus(connectionId));
  }

  /// Streams a local file ([sourcePath]) to the server. Returns the transfer
  /// id, or 0 when the engine rejected the request.
  static int uploadFile({
    required int connectionId,
    required int channelId,
    required String remotePath,
    required String sourcePath,
    String? channelPassword,
    bool overwrite = false,
  }) {
    final remotePtr = _strToPtr(remotePath);
    final sourcePtr = _strToPtr(sourcePath);
    final passwordPtr = _strToPtr(channelPassword);
    try {
      return _uploadFile(
        connectionId,
        channelId,
        remotePtr,
        passwordPtr,
        sourcePtr,
        overwrite ? 1 : 0,
      );
    } finally {
      _freeInputString(remotePtr);
      _freeInputString(sourcePtr);
      _freeInputString(passwordPtr);
    }
  }

  /// Requests the file listing of a channel directory (`ftgetfilelist`).
  ///
  /// Returns the `request_id` that the asynchronous `file_list` event carries
  /// back, or 0 when the request was rejected locally.
  static int listFiles({
    required int connectionId,
    required int channelId,
    required String path,
    String? channelPassword,
  }) {
    final pathPtr = _strToPtr(path);
    final passwordPtr = _strToPtr(channelPassword);
    try {
      return _listFiles(connectionId, channelId, pathPtr, passwordPtr);
    } finally {
      _freeInputString(pathPtr);
      _freeInputString(passwordPtr);
    }
  }

  /// Deletes a file from a channel directory (`ftdeletefile`).
  static bool deleteFile({
    required int connectionId,
    required int channelId,
    required String path,
    String? channelPassword,
  }) {
    final pathPtr = _strToPtr(path);
    final passwordPtr = _strToPtr(channelPassword);
    try {
      return _deleteFile(connectionId, channelId, pathPtr, passwordPtr) != 0;
    } finally {
      _freeInputString(pathPtr);
      _freeInputString(passwordPtr);
    }
  }

  /// Creates a directory in a channel (`ftcreatedir`).
  static bool createDirectory({
    required int connectionId,
    required int channelId,
    required String path,
    String? channelPassword,
  }) {
    final pathPtr = _strToPtr(path);
    final passwordPtr = _strToPtr(channelPassword);
    try {
      return _createDir(connectionId, channelId, pathPtr, passwordPtr) != 0;
    } finally {
      _freeInputString(pathPtr);
      _freeInputString(passwordPtr);
    }
  }

  /// Renames a file in a channel (`ftrenamefile`), optionally moving it to
  /// [targetChannelId] (with [targetChannelPassword]).
  static bool renameFile({
    required int connectionId,
    required int channelId,
    required String oldName,
    required String newName,
    String? channelPassword,
    int? targetChannelId,
    String? targetChannelPassword,
  }) {
    final oldPtr = _strToPtr(oldName);
    final newPtr = _strToPtr(newName);
    final passwordPtr = _strToPtr(channelPassword);
    final targetPasswordPtr = _strToPtr(targetChannelPassword);
    try {
      return _renameFile(
            connectionId,
            channelId,
            oldPtr,
            newPtr,
            passwordPtr,
            targetChannelId ?? 0,
            targetPasswordPtr,
          ) !=
          0;
    } finally {
      _freeInputString(oldPtr);
      _freeInputString(newPtr);
      _freeInputString(passwordPtr);
      _freeInputString(targetPasswordPtr);
    }
  }

  /// Requests the metadata of a file (`ftgetfileinfo`). Returns the
  /// `request_id` that the asynchronous `file_info` event carries back, or 0
  /// when the request was rejected locally.
  static int fileInfo({
    required int connectionId,
    required int channelId,
    required String name,
    String? channelPassword,
  }) {
    final namePtr = _strToPtr(name);
    final passwordPtr = _strToPtr(channelPassword);
    try {
      return _fileInfo(connectionId, channelId, namePtr, passwordPtr);
    } finally {
      _freeInputString(namePtr);
      _freeInputString(passwordPtr);
    }
  }

  /// Uses a privilege key (permission token) on this server
  /// (`privilegekeyuse`). The server confirms with a `token_used` event.
  static bool useToken(int connectionId, String token) {
    debugLog('useToken(len=${token.length})');
    final ptr = _strToPtr(token);
    try {
      return _useToken(connectionId, ptr) != 0;
    } finally {
      _freeInputString(ptr);
    }
  }

  /// Creates a channel. The server enforces the create permission.
  static bool createChannel({
    required int connectionId,
    required int parentId,
    required String name,
    String? topic,
    String? description,
    String? password,
    int? maxClients,
    bool permanent = false,
    bool semiPermanent = false,
  }) {
    final namePtr = _strToPtr(name);
    final topicPtr = _strToPtr(topic);
    final descPtr = _strToPtr(description);
    final passwordPtr = _strToPtr(password);
    try {
      return _createChannel(
            connectionId,
            parentId,
            namePtr,
            topicPtr,
            descPtr,
            passwordPtr,
            maxClients ?? 0,
            permanent ? 1 : 0,
            semiPermanent ? 1 : 0,
          ) !=
          0;
    } finally {
      _freeInputString(namePtr);
      _freeInputString(topicPtr);
      _freeInputString(descPtr);
      _freeInputString(passwordPtr);
    }
  }

  /// Edits a channel. Null strings leave the corresponding field unchanged.
  /// A non-null [hasPassword] overrides the password flag explicitly.
  static bool editChannel({
    required int connectionId,
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
    final namePtr = _strToPtr(name);
    final topicPtr = _strToPtr(topic);
    final descPtr = _strToPtr(description);
    final passwordPtr = _strToPtr(password);
    try {
      return _editChannel(
            connectionId,
            channelId,
            namePtr,
            topicPtr,
            descPtr,
            passwordPtr,
            hasPassword == null ? -1 : (hasPassword ? 1 : 0),
            maxClients ?? 0,
            permanent == null ? -1 : (permanent ? 1 : 0),
            semiPermanent == null ? -1 : (semiPermanent ? 1 : 0),
          ) !=
          0;
    } finally {
      _freeInputString(namePtr);
      _freeInputString(topicPtr);
      _freeInputString(descPtr);
      _freeInputString(passwordPtr);
    }
  }

  /// Deletes a channel. [force] deletes the tree even with sub-channels.
  static bool deleteChannel({
    required int connectionId,
    required int channelId,
    bool force = false,
  }) {
    return _deleteChannel(connectionId, channelId, force ? 1 : 0) != 0;
  }

  /// Moves/re-orders a channel in the tree.
  static bool moveChannelTree({
    required int connectionId,
    required int channelId,
    required int parentId,
    int? order,
  }) {
    return _moveChannelTree(connectionId, channelId, parentId, order ?? 0) != 0;
  }
}

/// FFI-level tracing. Goes through the central logger, so arguments that
/// slipped into a message (addresses, nicknames) are redacted and nothing is
/// printed at all in release builds.
void debugLog(String msg) {
  AppLog.d('ffi', msg);
}
