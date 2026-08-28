import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/services/app_log.dart';
import 'package:NEk0/services/connectivity_service.dart';

void main() {
  group('AppLog.redact', () {
    test('removes server addresses with and without a port', () {
      final withPort = AppLog.redact('connect to ts.example.test:9987 now');
      expect(withPort, isNot(contains('ts.example.test')));
      expect(withPort, contains(AppLog.placeholder));

      expect(
        AppLog.redact('resolved voice.guild.example.org'),
        isNot(contains('guild')),
      );
      expect(
        AppLog.redact('peer 192.168.1.40:9987 timed out'),
        isNot(contains('192.168.1.40')),
      );
    });

    test('removes values of sensitive keys even when they look harmless', () {
      final line = AppLog.redact('password=hunter2 nickname=Bob token=abc');
      expect(line, isNot(contains('hunter2')));
      expect(line, isNot(contains('Bob')));
      expect(line, isNot(contains('abc')));
      // The key names survive, so the log still says what was hidden.
      expect(line, contains('password'));
      expect(line, contains('nickname'));
    });

    test('removes identity and UID blobs', () {
      const uid = 'MqQbPnn9nJEK7X8xLC2ZZzMr0T4mE3sPuAzQvHt2fLg=';
      expect(AppLog.redact('client $uid joined'), isNot(contains(uid)));
    });

    test('keeps ordinary diagnostics readable', () {
      const message = 'poll got 3 events';
      expect(AppLog.redact(message), message);
    });

    test('is idempotent', () {
      final once = AppLog.redact('connect ts.example.test:9987');
      expect(AppLog.redact(once), once);
    });
  });

  group('AppLog levels', () {
    tearDown(() => AppLog.minLevel = LogLevel.debug);

    test('drops records below the minimum level', () {
      final printed = <String>[];
      // debugPrint is global; capture it to assert the filter really applies.
      final original = debugPrintSynchronously;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };
      addTearDown(() => debugPrint = original);

      AppLog.minLevel = LogLevel.warn;
      AppLog.d('test', 'debug line');
      AppLog.i('test', 'info line');
      AppLog.w('test', 'warn line');
      AppLog.e('test', 'error line', StateError('boom'));

      expect(printed.where((l) => l.contains('debug line')), isEmpty);
      expect(printed.where((l) => l.contains('info line')), isEmpty);
      expect(printed.where((l) => l.contains('warn line')), hasLength(1));
      expect(printed.where((l) => l.contains('error line')), hasLength(1));
    });

    test('error logs the exception type, never its message', () {
      final printed = <String>[];
      final original = debugPrintSynchronously;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };
      addTearDown(() => debugPrint = original);

      AppLog.minLevel = LogLevel.debug;
      AppLog.e('test', 'write failed', StateError('password=hunter2'));

      expect(printed.single, contains('StateError'));
      expect(printed.single, isNot(contains('hunter2')));
    });
  });

  group('NetworkStatus', () {
    const wifi = NetworkStatus(
      available: true,
      transport: 'wifi',
      networkId: 'net-1',
    );
    const cellular = NetworkStatus(
      available: true,
      transport: 'cellular',
      networkId: 'net-2',
    );
    const offline = NetworkStatus(
      available: false,
      transport: 'none',
      networkId: '',
    );

    test('detects a Wi-Fi to mobile handover', () {
      expect(cellular.isHandoverFrom(wifi), isTrue);
    });

    test('the same network reported twice is not a handover', () {
      expect(wifi.isHandoverFrom(wifi), isFalse);
    });

    test('coming back from offline is not a handover', () {
      // That case is a plain reconnect, handled by the retry path.
      expect(wifi.isHandoverFrom(offline), isFalse);
      expect(offline.isHandoverFrom(wifi), isFalse);
    });
  });
}
