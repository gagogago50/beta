import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-contact settings (the Windows client's "contacts" table).
///
/// The official client persists, per server + user UID, a set of flags and a
/// custom name. We store the same logical fields, keyed by `serverUid` +
/// client `uid`, so they follow a user across reconnects and servers.
///
/// This is a pure value object + persistence helper (no platform calls beyond
/// SharedPreferences), so it is unit-testable.
class ContactSettings {
  final String serverUid;
  final String uid;

  /// Optional display name override (mode 1) or prefix (mode 0).
  final String customName;

  /// 0 = `[customName] nickname`, 1 = `customName` only, 2 = nickname only.
  final int displayMode;

  final bool muted;
  final bool ignorePublicChat;
  final bool ignorePrivateChat;
  final bool ignorePokes;
  final bool hideAway;
  final bool hideAvatar;
  final bool allowWhispers;

  /// Linear volume modifier applied by the engine (−20..+20 dB elsewhere).
  final double volumeModifier;

  const ContactSettings({
    required this.serverUid,
    required this.uid,
    this.customName = '',
    this.displayMode = 2,
    this.muted = false,
    this.ignorePublicChat = false,
    this.ignorePrivateChat = false,
    this.ignorePokes = false,
    this.hideAway = false,
    this.hideAvatar = false,
    this.allowWhispers = false,
    this.volumeModifier = 0.0,
  });

  /// The name to show, matching the Windows client's `preferredDisplayName`.
  String preferredDisplayName(String serverNickname) {
    if (displayMode == 1 && customName.isNotEmpty) return customName;
    if (displayMode == 0 && customName.isNotEmpty) {
      // [SOURCE] `[customName] nickname`.
      return '[${customName}] ${serverNickname.isEmpty ? '' : serverNickname}';
    }
    return serverNickname.isEmpty ? uid : serverNickname;
  }

  ContactSettings copyWith({
    String? customName,
    int? displayMode,
    bool? muted,
    bool? ignorePublicChat,
    bool? ignorePrivateChat,
    bool? ignorePokes,
    bool? hideAway,
    bool? hideAvatar,
    bool? allowWhispers,
    double? volumeModifier,
  }) => ContactSettings(
    serverUid: serverUid,
    uid: uid,
    customName: customName ?? this.customName,
    displayMode: displayMode ?? this.displayMode,
    muted: muted ?? this.muted,
    ignorePublicChat: ignorePublicChat ?? this.ignorePublicChat,
    ignorePrivateChat: ignorePrivateChat ?? this.ignorePrivateChat,
    ignorePokes: ignorePokes ?? this.ignorePokes,
    hideAway: hideAway ?? this.hideAway,
    hideAvatar: hideAvatar ?? this.hideAvatar,
    allowWhispers: allowWhispers ?? this.allowWhispers,
    volumeModifier: volumeModifier ?? this.volumeModifier,
  );

  Map<String, dynamic> toJson() => {
    'serverUid': serverUid,
    'uid': uid,
    'customName': customName,
    'displayMode': displayMode,
    'muted': muted,
    'ignorePublicChat': ignorePublicChat,
    'ignorePrivateChat': ignorePrivateChat,
    'ignorePokes': ignorePokes,
    'hideAway': hideAway,
    'hideAvatar': hideAvatar,
    'allowWhispers': allowWhispers,
    'volumeModifier': volumeModifier,
  };

  factory ContactSettings.fromJson(Map<String, dynamic> json) =>
      ContactSettings(
        serverUid: json['serverUid'] as String? ?? '',
        uid: json['uid'] as String? ?? '',
        customName: json['customName'] as String? ?? '',
        displayMode: json['displayMode'] as int? ?? 2,
        muted: json['muted'] as bool? ?? false,
        ignorePublicChat: json['ignorePublicChat'] as bool? ?? false,
        ignorePrivateChat: json['ignorePrivateChat'] as bool? ?? false,
        ignorePokes: json['ignorePokes'] as bool? ?? false,
        hideAway: json['hideAway'] as bool? ?? false,
        hideAvatar: json['hideAvatar'] as bool? ?? false,
        allowWhispers: json['allowWhispers'] as bool? ?? false,
        volumeModifier: (json['volumeModifier'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Persists [ContactSettings] in SharedPreferences, one JSON string per
/// (serverUid, uid) key.
class ContactStore {
  ContactStore._();

  static String _key(String serverUid, String uid) =>
      'contact_${serverUid}_$uid';

  static Future<void> save(ContactSettings c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(c.serverUid, c.uid), jsonEncode(c.toJson()));
  }

  static Future<ContactSettings?> load(String serverUid, String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(serverUid, uid));
    if (raw == null) return null;
    try {
      return ContactSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String serverUid, String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(serverUid, uid));
  }

  /// All contacts for a given server (for a future "contacts" screen).
  static Future<List<ContactSettings>> forServer(String serverUid) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'contact_${serverUid}_';
    final out = <ContactSettings>[];
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith(prefix)) continue;
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        out.add(
          ContactSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {}
    }
    return out;
  }
}
