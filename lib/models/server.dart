class Server {
  final String id;
  final String name;
  final String address;
  final String nickname;
  final String? channel;
  final String? password;
  final String? channelPassword;

  Server({
    required this.id,
    required this.name,
    required this.address,
    required this.nickname,
    this.channel,
    this.password,
    this.channelPassword,
  });

  /// Non-sensitive bookmark data only. Passwords are stored separately by
  /// [SecureStorage] using this server's ID and must never be serialized here.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'nickname': nickname,
    'channel': channel,
  };

  /// Copy helper. [clearPassword]/[clearChannelPassword] exist because a
  /// nullable named parameter cannot distinguish "unchanged" from "erase",
  /// and erasing is exactly what the secret-wipe command needs.
  Server copyWith({
    String? name,
    String? address,
    String? nickname,
    String? channel,
    String? password,
    String? channelPassword,
    bool clearPassword = false,
    bool clearChannelPassword = false,
  }) => Server(
    id: id,
    name: name ?? this.name,
    address: address ?? this.address,
    nickname: nickname ?? this.nickname,
    channel: channel ?? this.channel,
    password: clearPassword ? null : (password ?? this.password),
    channelPassword: clearChannelPassword
        ? null
        : (channelPassword ?? this.channelPassword),
  );

  factory Server.fromJson(Map<String, dynamic> json) => Server(
    id: json['id'] as String,
    name: json['name'] as String,
    address: json['address'] as String,
    nickname: json['nickname'] as String,
    channel: json['channel'] as String?,
    password: json['password'] as String?,
    channelPassword: json['channel_password'] as String?,
  );
}
