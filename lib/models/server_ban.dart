/// One entry of the server ban table, as reported by the engine's `ban_list`
/// event (a `banlist` reply).
class ServerBan {
  final int banId;
  final String ip;
  final String name;
  final String uid;
  final String lastNickname;
  final int created;
  final int duration;
  final String invokerName;

  const ServerBan({
    required this.banId,
    this.ip = '',
    this.name = '',
    this.uid = '',
    this.lastNickname = '',
    this.created = 0,
    this.duration = 0,
    this.invokerName = '',
  });

  factory ServerBan.fromJson(Map<String, dynamic> json) => ServerBan(
    banId: (json['ban_id'] as num?)?.toInt() ?? 0,
    ip: json['ip'] as String? ?? '',
    name: json['name'] as String? ?? '',
    uid: json['uid'] as String? ?? '',
    lastNickname: json['last_nickname'] as String? ?? '',
    created: (json['created'] as num?)?.toInt() ?? 0,
    duration: (json['duration'] as num?)?.toInt() ?? 0,
    invokerName: json['invoker_name'] as String? ?? '',
  );

  /// Human label for the banned entity (nickname > last nickname > IP > UID).
  String get label {
    if (name.isNotEmpty) return name;
    if (lastNickname.isNotEmpty) return lastNickname;
    if (ip.isNotEmpty) return ip;
    if (uid.isNotEmpty) return uid;
    return 'ban #$banId';
  }

  /// Whether the ban is permanent (`duration == 0` means indefinite).
  bool get permanent => duration <= 0;

  String get durationLabel => permanent ? 'Permanent' : '${duration ~/ 60} min';
}
