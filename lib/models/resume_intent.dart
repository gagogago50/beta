import 'package:shared_preferences/shared_preferences.dart';

/// A durable "resume" intent kept across process death.
///
/// TeamSpeak state (connections, channels, mute toggles) lives only in memory;
/// if Android kills the app the user loses where they were. This records the
/// parameters of the *last successful* connection so the app can offer to
/// rejoin after a restart — without ever auto-opening the microphone.
class ResumeIntent {
  final String address;
  final String nickname;
  final String? channel;

  /// Whether the microphone was muted at the moment the process died. On
  /// resume we always restore this, and default to *muted* if unknown, so a
  /// kill never leaves the mic live unexpectedly.
  final bool micWasMuted;

  const ResumeIntent({
    required this.address,
    required this.nickname,
    this.channel,
    this.micWasMuted = true,
  });

  bool get hasCredentials => address.isNotEmpty && nickname.isNotEmpty;

  ResumeIntent copyWith({
    String? address,
    String? nickname,
    String? channel,
    bool? micWasMuted,
  }) => ResumeIntent(
    address: address ?? this.address,
    nickname: nickname ?? this.nickname,
    channel: channel ?? this.channel,
    micWasMuted: micWasMuted ?? this.micWasMuted,
  );
}

/// Persistence for [ResumeIntent] in SharedPreferences. Stored without any
/// password (the saved server/password already lives in Keystore under the
/// server id); the intent only holds an address + nickname to rejoin.
class ResumeIntentStore {
  ResumeIntentStore._();

  static const _key = 'resume_intent';

  static Future<void> save(ResumeIntent intent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      [
        intent.address,
        intent.nickname,
        intent.channel ?? '',
        intent.micWasMuted ? '1' : '0',
      ].join('\u0000'),
    );
  }

  static Future<ResumeIntent?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('\u0000');
    if (parts.length < 2) return null;
    return ResumeIntent(
      address: parts[0],
      nickname: parts[1],
      channel: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null,
      micWasMuted: parts.length > 3 ? parts[3] != '0' : true,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
