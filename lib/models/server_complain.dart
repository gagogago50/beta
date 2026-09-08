/// One complaint against a user, as reported by the engine's `complain_list`
/// event (a `complainlist` reply).
class ServerComplain {
  final int targetDbId;
  final String targetName;
  final int fromDbId;
  final String fromName;
  final String message;
  final int timestamp;

  const ServerComplain({
    required this.targetDbId,
    this.targetName = '',
    this.fromDbId = 0,
    this.fromName = '',
    this.message = '',
    this.timestamp = 0,
  });

  factory ServerComplain.fromJson(Map<String, dynamic> json) => ServerComplain(
    targetDbId: (json['target_db_id'] as num?)?.toInt() ?? 0,
    targetName: json['target_name'] as String? ?? '',
    fromDbId: (json['from_db_id'] as num?)?.toInt() ?? 0,
    fromName: json['from_name'] as String? ?? '',
    message: json['message'] as String? ?? '',
    timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
  );
}
