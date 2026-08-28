import 'dart:math';

/// Phases of the connection state machine.
///
/// The engine drives `resolving` → `connecting` → `authenticating` →
/// `connected`; `reconnecting` and `failed` are owned by the client-side
/// retry policy.
enum TsPhase {
  idle,
  resolving,
  connecting,
  authenticating,
  connected,
  reconnecting,
  failed;

  static TsPhase fromNative(String value) => switch (value) {
    'resolving' => TsPhase.resolving,
    'connecting' => TsPhase.connecting,
    'authenticating' => TsPhase.authenticating,
    'connected' => TsPhase.connected,
    _ => TsPhase.idle,
  };

  bool get isBusy =>
      this == TsPhase.resolving ||
      this == TsPhase.connecting ||
      this == TsPhase.authenticating ||
      this == TsPhase.reconnecting;
}

/// Client-side automatic reconnection policy.
///
/// Deliberately conservative: TeamSpeak servers rate-limit and ban clients
/// that hammer the handshake, so retries are capped, exponential, jittered and
/// only ever attempted for failures a retry can actually fix.
class ReconnectPolicy {
  /// Failure kinds (as reported by the Rust engine) that must never be
  /// retried automatically — retrying cannot change the outcome and, for
  /// `banned`/`password`, would look like an attack to the server.
  static const nonRetryableKinds = <String>{
    'password',
    'channel_password',
    'banned',
    'nickname_in_use',
    'identity_level',
    'server_identity_changed',
    'server_refused',
    'protocol',
    'cancelled',
  };

  static const maxAttempts = 6;
  static const baseDelay = Duration(seconds: 2);
  static const maxDelay = Duration(seconds: 30);

  /// Jitter fraction applied to each delay (±20%), so several clients dropped
  /// by the same server restart do not come back in lockstep.
  static const jitterFraction = 0.2;

  const ReconnectPolicy._();

  static bool shouldRetry({
    required String kind,
    required bool retryable,
    required int attempt,
  }) {
    if (!retryable) return false;
    if (nonRetryableKinds.contains(kind)) return false;
    return attempt < maxAttempts;
  }

  /// Exponential backoff with full ±[jitterFraction] jitter.
  ///
  /// [attempt] is 0-based: attempt 0 waits ~2s, 1 → ~4s, 2 → ~8s … capped at
  /// [maxDelay]. [random] is injectable so the behaviour is testable.
  static Duration delayFor(int attempt, {Random? random}) {
    final rng = random ?? Random();
    final exponent = attempt.clamp(0, 16);
    final raw = baseDelay.inMilliseconds * pow(2, exponent);
    final capped = min(raw.toDouble(), maxDelay.inMilliseconds.toDouble());
    // rng.nextDouble() ∈ [0,1) → factor ∈ [0.8, 1.2)
    final factor = 1.0 + (rng.nextDouble() * 2 - 1) * jitterFraction;
    return Duration(milliseconds: (capped * factor).round());
  }
}
