import 'package:flutter/foundation.dart';

/// Severity of a log record. Anything below [AppLog.minLevel] is dropped
/// before the message is even built.
enum LogLevel { debug, info, warn, error }

/// Central application logger.
///
/// Two rules drive this file:
///
/// 1. **Nothing sensitive reaches logcat.** Server addresses, nicknames,
///    passwords, identity material and UIDs identify both the user and the
///    servers they join; on Android any app with READ_LOGS-adjacent tooling
///    (or a bug report) can read them. Every message goes through [redact].
/// 2. **Release builds are quiet.** Debug/info logging is compiled out of
///    release through [kReleaseMode]: warnings and errors still surface,
///    without payloads.
class AppLog {
  const AppLog._();

  /// Minimum level actually printed. Debug builds keep everything; release
  /// builds only keep warnings and errors.
  static LogLevel minLevel = kReleaseMode ? LogLevel.warn : LogLevel.debug;

  /// Replacement token, deliberately visible so a redacted log is obviously
  /// redacted rather than looking like missing data.
  static const placeholder = '<redacted>';

  // Matches host:port and bare hostnames/IPv4 of a TeamSpeak server.
  static final _address = RegExp(
    r'\b(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}(?::\d{1,5})?\b'
    r'|\b\d{1,3}(?:\.\d{1,3}){3}(?::\d{1,5})?\b',
  );

  // key=value / key: value / "key": "value" for sensitive keys.
  static final _keyed = RegExp(
    r'''(?<key>password|passwd|pwd|token|secret|identity|client_identity|uid|nickname|nick)'''
    r'''(?<sep>"?\s*[:=]\s*"?)(?<value>[^\s,;}"]+)''',
    caseSensitive: false,
  );

  // TeamSpeak identities and UIDs are long base64 blobs.
  static final _blob = RegExp(r'\b[A-Za-z0-9+/]{24,}={0,2}\b');

  /// Strips anything that identifies the user or the server they connect to.
  ///
  /// Order matters: keyed values first (so `password=example.com` loses the
  /// value, not just the host shape), then blobs, then bare addresses.
  static String redact(String message) {
    var result = message.replaceAllMapped(_keyed, (match) {
      final m = match as RegExpMatch;
      return '${m.namedGroup('key')}${m.namedGroup('sep')}$placeholder';
    });
    result = result.replaceAll(_blob, placeholder);
    result = result.replaceAll(_address, placeholder);
    return result;
  }

  static void log(LogLevel level, String tag, String message) {
    if (level.index < minLevel.index) return;
    final prefix = switch (level) {
      LogLevel.debug => 'D',
      LogLevel.info => 'I',
      LogLevel.warn => 'W',
      LogLevel.error => 'E',
    };
    debugPrint('[$prefix/$tag] ${redact(message)}');
  }

  static void d(String tag, String message) =>
      log(LogLevel.debug, tag, message);

  static void i(String tag, String message) => log(LogLevel.info, tag, message);

  static void w(String tag, String message) => log(LogLevel.warn, tag, message);

  /// Errors log the exception **type**, never the instance: exception
  /// messages routinely embed the offending value (a URL, a key, a password).
  static void e(String tag, String message, [Object? error]) {
    final suffix = error == null ? '' : ' (${error.runtimeType})';
    log(LogLevel.error, tag, '$message$suffix');
  }
}
