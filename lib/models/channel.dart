class TsChannel {
  final int id;
  final String name;
  final int parentId;
  final String topic;
  final bool hasPassword;
  final int clientCount;
  final int order;

  /// Talk power required to speak in this channel.
  final int neededTalkPower;

  /// Maximum number of clients: `-1` = unlimited, `-2` = inherited, else cap.
  final int maxClients;

  /// TeamSpeak codec id: 0=Speex NB, 1=Speex WB, 2=Speex UWB, 3=Celt mono,
  /// 4=Opus voice, 5=Opus music.
  final int codec;

  /// Codec quality 0..10, when the server reports it.
  final int codecQuality;

  /// 0 = temporary (deleted when empty), 1 = permanent (survives restart),
  /// 2 = semi-permanent (deleted on server restart).
  final int channelType;

  /// Whether this is the server's default channel.
  final bool isDefault;

  /// Whether the channel is private (`channel_flag_private`).
  final bool isPrivate;

  /// Whether we are subscribed to this channel (we hear it).
  final bool subscribed;

  /// Channel icon id, 0 when the channel has none.
  final int iconId;

  /// Whether the channel's voice is transmitted unencrypted.
  final bool isUnencrypted;

  const TsChannel({
    required this.id,
    required this.name,
    required this.parentId,
    this.topic = '',
    this.hasPassword = false,
    this.clientCount = 0,
    this.order = 0,
    this.neededTalkPower = 0,
    this.maxClients = -1,
    this.codec = 4,
    this.codecQuality = 0,
    this.channelType = 0,
    this.isDefault = false,
    this.isPrivate = false,
    this.subscribed = true,
    this.iconId = 0,
    this.isUnencrypted = true,
  });

  factory TsChannel.fromJson(Map<String, dynamic> json) => TsChannel(
    id: json['id'] as int,
    name: json['name'] as String,
    parentId: json['parent_id'] as int,
    topic: json['topic'] as String? ?? '',
    hasPassword: json['has_password'] as bool? ?? false,
    clientCount: json['client_count'] as int? ?? 0,
    order: json['order'] as int? ?? 0,
    neededTalkPower: json['needed_talk_power'] as int? ?? 0,
    maxClients: json['max_clients'] as int? ?? -1,
    codec: json['codec'] as int? ?? 4,
    codecQuality: json['codec_quality'] as int? ?? 0,
    channelType: json['channel_type'] as int? ?? 0,
    isDefault: json['is_default'] as bool? ?? false,
    isPrivate: json['is_private'] as bool? ?? false,
    subscribed: json['subscribed'] as bool? ?? true,
    iconId: json['icon_id'] as int? ?? 0,
    isUnencrypted: json['is_unencrypted'] as bool? ?? true,
  );

  /// True for a permanent channel (survives a server restart).
  bool get isPermanent => channelType == 1;

  /// True for a semi-permanent channel (deleted on server restart).
  bool get isSemiPermanent => channelType == 2;

  /// True when the client cap is unlimited (0 means unlimited in TS semantics,
  /// mapped from the engine's -1).
  bool get isUnlimitedClients => maxClients <= 0;

  List<TsChannel> children(List<TsChannel> all) {
    return all.where((c) => c.parentId == id).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }
}
