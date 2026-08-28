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
  );

  TsClient copyWith({bool? isTalking, bool? isWhispering, double? volume}) =>
      TsClient(
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
        inputMuted: inputMuted,
        outputMuted: outputMuted,
        isTalking: isTalking ?? this.isTalking,
        isWhispering: isWhispering ?? this.isWhispering,
        volume: volume ?? this.volume,
        permissions: permissions,
        uid: uid,
      );

  /// Every group icon of this client, channel group first, zeros removed.
  List<int> get groupIconIds => [
    if (channelGroupIconId != 0) channelGroupIconId,
    ...serverGroupIconIds.where((id) => id != 0),
  ];
}
