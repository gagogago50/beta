import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/poll_policy.dart';

void main() {
  group('PollPolicy.intervalFor', () {
    test('backgrounded always uses the slow safety tier', () {
      // Even while capturing: in the background nothing displays the mic
      // indicator, and voice does not travel through this timer.
      for (final capturing in [true, false]) {
        for (final connected in [true, false]) {
          expect(
            PollPolicy.intervalFor(
              connected: connected,
              capturing: capturing,
              foreground: false,
            ),
            PollPolicy.background,
          );
        }
      }
    });

    test('foreground capturing is the fast tier', () {
      expect(
        PollPolicy.intervalFor(
          connected: true,
          capturing: true,
          foreground: true,
        ),
        PollPolicy.capturing,
      );
    });

    test('foreground connected and idle backs off', () {
      expect(
        PollPolicy.intervalFor(
          connected: true,
          capturing: false,
          foreground: true,
        ),
        PollPolicy.foregroundIdle,
      );
    });

    test('while connecting the cadence stays responsive', () {
      expect(
        PollPolicy.intervalFor(
          connected: false,
          capturing: false,
          foreground: true,
        ),
        PollPolicy.connecting,
      );
    });

    test('tiers are ordered from fastest to slowest', () {
      expect(PollPolicy.capturing, lessThan(PollPolicy.foregroundIdle));
      expect(PollPolicy.foregroundIdle, lessThan(PollPolicy.background));
      // The background tier must stay well under any server timeout so the
      // safety net is still a net.
      expect(PollPolicy.background.inSeconds, lessThanOrEqualTo(30));
    });

    test('the background tier is a large win over the old fixed cadence', () {
      // The upstream client polled every 200ms unconditionally.
      const upstream = Duration(milliseconds: 200);
      final ratio =
          PollPolicy.background.inMilliseconds / upstream.inMilliseconds;
      expect(ratio, greaterThanOrEqualTo(50));
    });
  });

  group('PollPolicy.shouldReconcileRoster', () {
    test('only reconciles the roster while visible', () {
      expect(PollPolicy.shouldReconcileRoster(foreground: true), isTrue);
      // Serializing every client to JSON with nothing to draw is pure drain.
      expect(PollPolicy.shouldReconcileRoster(foreground: false), isFalse);
    });
  });
}
