import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/reconnect_policy.dart';

void main() {
  group('ReconnectPolicy.shouldRetry', () {
    test('never retries a rejected password or a ban', () {
      for (final kind in ['password', 'channel_password', 'banned']) {
        expect(
          ReconnectPolicy.shouldRetry(kind: kind, retryable: true, attempt: 0),
          isFalse,
          reason: '$kind must not be retried automatically',
        );
      }
    });

    test('never retries a user cancellation', () {
      expect(
        ReconnectPolicy.shouldRetry(
          kind: 'cancelled',
          retryable: true,
          attempt: 0,
        ),
        isFalse,
      );
    });

    test('retries transient transport failures within the attempt budget', () {
      for (final kind in ['timeout', 'dns', 'network', 'connection_lost']) {
        expect(
          ReconnectPolicy.shouldRetry(kind: kind, retryable: true, attempt: 0),
          isTrue,
        );
      }
    });

    test('honours the engine retryable flag', () {
      expect(
        ReconnectPolicy.shouldRetry(
          kind: 'network',
          retryable: false,
          attempt: 0,
        ),
        isFalse,
      );
    });

    test('stops after the maximum number of attempts', () {
      expect(
        ReconnectPolicy.shouldRetry(
          kind: 'timeout',
          retryable: true,
          attempt: ReconnectPolicy.maxAttempts - 1,
        ),
        isTrue,
      );
      expect(
        ReconnectPolicy.shouldRetry(
          kind: 'timeout',
          retryable: true,
          attempt: ReconnectPolicy.maxAttempts,
        ),
        isFalse,
      );
    });
  });

  group('ReconnectPolicy.delayFor', () {
    test('grows exponentially and is capped', () {
      // Random fixed at 0.5 → jitter factor exactly 1.0.
      final noJitter = _FixedRandom(0.5);
      expect(
        ReconnectPolicy.delayFor(0, random: noJitter),
        ReconnectPolicy.baseDelay,
      );
      expect(
        ReconnectPolicy.delayFor(1, random: noJitter),
        ReconnectPolicy.baseDelay * 2,
      );
      expect(
        ReconnectPolicy.delayFor(2, random: noJitter),
        ReconnectPolicy.baseDelay * 4,
      );
      expect(
        ReconnectPolicy.delayFor(20, random: noJitter),
        ReconnectPolicy.maxDelay,
      );
    });

    test('stays inside the +/-20% jitter window', () {
      for (final value in [0.0, 0.25, 0.999]) {
        final delay = ReconnectPolicy.delayFor(3, random: _FixedRandom(value));
        // attempt 3 → 16s, capped at 30s → 16s ± 20%
        expect(delay.inMilliseconds, greaterThanOrEqualTo(12800));
        expect(delay.inMilliseconds, lessThanOrEqualTo(19200));
      }
    });

    test('never returns a negative or zero delay', () {
      final rng = Random(42);
      for (var attempt = 0; attempt < 10; attempt++) {
        expect(
          ReconnectPolicy.delayFor(attempt, random: rng).inMilliseconds,
          greaterThan(0),
        );
      }
    });
  });

  group('TsPhase', () {
    test('maps engine phase names', () {
      expect(TsPhase.fromNative('resolving'), TsPhase.resolving);
      expect(TsPhase.fromNative('authenticating'), TsPhase.authenticating);
      expect(TsPhase.fromNative('connected'), TsPhase.connected);
      // Unknown values must degrade instead of throwing.
      expect(TsPhase.fromNative('something-new'), TsPhase.idle);
    });

    test('isBusy covers every in-flight phase', () {
      expect(TsPhase.resolving.isBusy, isTrue);
      expect(TsPhase.connecting.isBusy, isTrue);
      expect(TsPhase.authenticating.isBusy, isTrue);
      expect(TsPhase.reconnecting.isBusy, isTrue);
      expect(TsPhase.connected.isBusy, isFalse);
      expect(TsPhase.idle.isBusy, isFalse);
      expect(TsPhase.failed.isBusy, isFalse);
    });
  });
}

/// Deterministic Random stub: always returns the same value for nextDouble.
class _FixedRandom implements Random {
  final double value;

  _FixedRandom(this.value);

  @override
  double nextDouble() => value;

  @override
  bool nextBool() => value >= 0.5;

  @override
  int nextInt(int max) => (value * max).floor();
}
