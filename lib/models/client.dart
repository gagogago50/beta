import 'client_permissions.dart';

class TsClient {
  final int id;
  final String nickname;
  final int channelId;
  final int channelGroupId;
  final String? channelGroupName;

  /// Icon of the channel group, 0 when there is none.
  final int channelGroupIconId;
  final List<int> serverGroupIds;
  final List<String> serverGroupNames;

  /// Icons of the server groups, index-aligned with [serverGroupNames].
  final List<int> serverGroupIconIds;
  final bool away;
  final bool inputMuted;
  final bool outputMuted;
  final bool isTalking;
  final bool isWhispering;
  final double volume;

  /// What the server allows *us* to do to this client (kick, ban, move…).
  final ClientPermissions permissions;
  final String? uid;

  /// 0 = normal user, 1 = server query (a bot / admin tool). Server-query
  /// clients have no nickname country and should never be treated as a human.
  final int clientType;
  final bool talkPowerGranted;

  /// `client_talk_power`: how much talk power this client holds.
  final int talkPower;
  final bool isPrioritySpeaker;

  /// Whether the client is the channel commander (server-granted).
  final bool isChannelCommander;

  /// `client_recording`: whether this client is recording the channel.
  final bool isRecording;

  /// Capture / output hardware flags, distinct from the "muted" flags (the
  /// desktop client shows "input deactivated" separately from "muted").
  final bool inputHardwareEnabled;
  final bool outputHardwareEnabled;

  /// Hears nothing but still transmits.
  final bool outputOnlyMuted;

  /// Phonetic rendition of the nickname, when the server provides one.
  final String phoneticName;

  /// ISO country code (e.g. "DE"), empty when unknown.
  final String countryCode;

  /// Free-form `client_meta_data`.
  final String metadata;

  /// MD5 of the avatar image, used to fetch it via the file-transfer channel.
  final String avatarHash;

  const TsClient({
    required this.id,
    required this.nickname,
    required this.channelId,
    this.channelGroupId = 0,
    this.channelGroupName,
    this.channelGroupIconId = 0,
    this.serverGroupIds = const [],
    this.serverGroupNames = const [],
    this.serverGroupIconIds = const [],
    this.away = false,
    this.inputMuted = false,
    this.outputMuted = false,
    this.isTalking = false,
    this.isWhispering = false,
    this.volume = 0.0,
    this.permissions = ClientPermissions.none,
    this.uid,
    this.clientType = 0,
    this.talkPowerGranted = false,
    this.talkPower = 0,
    this.isPrioritySpeaker = false,
    this.isChannelCommander = false,
    this.isRecording = false,
    this.inputHardwareEnabled = true,
    this.outputHardwareEnabled = true,
    this.outputOnlyMuted = false,
    this.phoneticName = '',
    this.countryCode = '',
    this.metadata = '',
    this.avatarHash = '',
  });

  factory TsClient.fromJson(Map<String, dynamic> json) => TsClient(
    id: json['id'] as int,
    nickname: json['nickname'] as String,
    channelId: json['channel_id'] as int,
    channelGroupId: json['channel_group_id'] as int? ?? 0,
    channelGroupName: json['channel_group_name'] as String?,
    channelGroupIconId: json['channel_group_icon_id'] as int? ?? 0,
    serverGroupIds: (json['server_group_ids'] as List<dynamic>? ?? const [])
        .map((value) => value as int)
        .toList(growable: false),
    serverGroupNames: (json['server_group_names'] as List<dynamic>? ?? const [])
        .map((value) => value as String)
        .toList(growable: false),
    serverGroupIconIds:
        (json['server_group_icon_ids'] as List<dynamic>? ?? const [])
            .map((value) => value as int)
            .toList(growable: false),
    away: json['away'] as bool? ?? false,
    inputMuted: json['input_muted'] as bool? ?? false,
    outputMuted: json['output_muted'] as bool? ?? false,
    isTalking: json['is_talking'] as bool? ?? false,
    isWhispering: json['is_whispering'] as bool? ?? false,
    permissions: ClientPermissions(json['permission_hints'] as int? ?? 0),
    volume: (json['volume'] as num?)?.toDouble() ?? 0.0,
    uid: json['uid'] as String?,
    clientType: json['client_type'] as int? ?? 0,
    talkPowerGranted: json['talk_power_granted'] as bool? ?? false,
    talkPower: json['talk_power'] as int? ?? 0,
    isPrioritySpeaker: json['is_priority_speaker'] as bool? ?? false,
    isChannelCommander: json['is_channel_commander'] as bool? ?? false,
    isRecording: json['is_recording'] as bool? ?? false,
    inputHardwareEnabled: json['input_hardware_enabled'] as bool? ?? true,
    outputHardwareEnabled: json['output_hardware_enabled'] as bool? ?? true,
    outputOnlyMuted: json['output_only_muted'] as bool? ?? false,
    phoneticName: json['phonetic_name'] as String? ?? '',
    countryCode: json['country_code'] as String? ?? '',
    metadata: json['metadata'] as String? ?? '',
    avatarHash: json['avatar_hash'] as String? ?? '',
  );

  TsClient copyWith({
    bool? isTalking,
    bool? isWhispering,
    double? volume,
    bool? inputMuted,
    bool? outputMuted,
  }) => TsClient(
    id: id,
    nickname: nickname,
    channelId: channelId,
    channelGroupId: channelGroupId,
    channelGroupName: channelGroupName,
    channelGroupIconId: channelGroupIconId,
    serverGroupIds: serverGroupIds,
    serverGroupNames: serverGroupNames,
    serverGroupIconIds: serverGroupIconIds,
    away: away,
    inputMuted: inputMuted ?? this.inputMuted,
    outputMuted: outputMuted ?? this.outputMuted,
    isTalking: isTalking ?? this.isTalking,
    isWhispering: isWhispering ?? this.isWhispering,
    volume: volume ?? this.volume,
    permissions: permissions,
    uid: uid,
    clientType: clientType,
    talkPowerGranted: talkPowerGranted,
    talkPower: talkPower,
    isPrioritySpeaker: isPrioritySpeaker,
    isChannelCommander: isChannelCommander,
    isRecording: isRecording,
    inputHardwareEnabled: inputHardwareEnabled,
    outputHardwareEnabled: outputHardwareEnabled,
    outputOnlyMuted: outputOnlyMuted,
    phoneticName: phoneticName,
    countryCode: countryCode,
    metadata: metadata,
    avatarHash: avatarHash,
  );

  /// True for a server-query client (bot / admin tool).
  bool get isQuery => clientType == 1;

  /// Every group icon of this client, channel group first, zeros removed.
  List<int> get groupIconIds => [
    if (channelGroupIconId != 0) channelGroupIconId,
    ...serverGroupIconIds.where((id) => id != 0),
  ];
}
