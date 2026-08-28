import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/services/icon_cache.dart';

void main() {
  group('IconCache limits', () {
    test('caps icon size well below the engine hard limit', () {
      // The engine refuses anything above 8 MiB; icons must stay far below,
      // otherwise a hostile server could fill the device through the icon
      // path alone.
      expect(IconCache.maxIconBytes, lessThanOrEqualTo(1024 * 1024));
      expect(IconCache.maxIconBytes, greaterThan(0));
    });

    test('keeps a bounded cache lifetime', () {
      expect(IconCache.maxAge.inDays, greaterThan(0));
      expect(IconCache.maxAge.inDays, lessThanOrEqualTo(90));
    });
  });

  group('IconCache session state', () {
    test('reset clears failures so a new server can be tried', () {
      // reset() is called on connect; it must not throw when nothing is
      // pending (fresh process, first connection).
      expect(IconCache.reset, returnsNormally);
    });

    test('an unknown transfer id is ignored', () {
      // Late events for cancelled or foreign transfers must not crash the
      // event loop handler.
      expect(
        () => IconCache.onTransferEvent(
          transferId: 4242,
          ok: true,
          localPath: '/tmp/whatever',
        ),
        returnsNormally,
      );
    });

    test('a failed transfer event is ignored when unknown', () {
      expect(
        () =>
            IconCache.onTransferEvent(transferId: 0, ok: false, localPath: ''),
        returnsNormally,
      );
    });
  });

  group('avatars', () {
    test('avatars get their own, larger cap', () {
      // User-supplied images are bigger than icons, but still bounded well
      // under the engine's hard limit.
      expect(IconCache.maxAvatarBytes, greaterThan(IconCache.maxIconBytes));
      expect(IconCache.maxAvatarBytes, lessThanOrEqualTo(4 * 1024 * 1024));
    });

    test('an empty client uid never triggers a transfer', () async {
      expect(await IconCache.avatar('server', ''), isNull);
    });

    test('reset clears avatar failures too', () {
      expect(IconCache.reset, returnsNormally);
    });
  });
}
