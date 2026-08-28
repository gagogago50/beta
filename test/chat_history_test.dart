import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/chat_message.dart';
import 'package:NEk0/services/chat_history_service.dart';

ChatMessage _message(String text, DateTime timestamp, {int id = 0}) =>
    ChatMessage(
      id: id,
      fromClient: 'Someone',
      fromClientId: 7,
      targetMode: 2,
      message: text,
      timestamp: timestamp,
    );

void main() {
  final now = DateTime(2026, 8, 23, 12);

  group('retention', () {
    test('drops messages older than the window', () {
      final messages = [
        _message('old', now.subtract(const Duration(days: 40))),
        _message('recent', now.subtract(const Duration(days: 3))),
      ];

      final kept = ChatHistoryService.prune(
        messages,
        retention: HistoryRetention.thirtyDays,
        now: now,
      );

      expect(kept.map((m) => m.message), ['recent']);
    });

    test('a shorter window drops more', () {
      final messages = [
        _message('ten days', now.subtract(const Duration(days: 10))),
        _message('two days', now.subtract(const Duration(days: 2))),
      ];

      expect(
        ChatHistoryService.prune(
          messages,
          retention: HistoryRetention.sevenDays,
          now: now,
        ).map((m) => m.message),
        ['two days'],
      );
      expect(
        ChatHistoryService.prune(
          messages,
          retention: HistoryRetention.ninetyDays,
          now: now,
        ),
        hasLength(2),
      );
    });

    test('caps the number of entries, keeping the newest', () {
      final messages = [
        for (var index = 0; index < 600; index++)
          _message(
            'message $index',
            now.subtract(Duration(minutes: 600 - index)),
            id: index,
          ),
      ];

      final kept = ChatHistoryService.prune(
        messages,
        retention: HistoryRetention.ninetyDays,
        now: now,
      );

      expect(kept, hasLength(ChatHistoryService.maxEntriesPerServer));
      expect(kept.last.message, 'message 599');
    });

    test('an unknown retention value falls back to 30 days', () {
      expect(HistoryRetention.fromDays(365), HistoryRetention.thirtyDays);
      expect(HistoryRetention.fromDays(7), HistoryRetention.sevenDays);
    });
  });

  group('serialization', () {
    test('round-trips a conversation', () {
      final messages = [
        _message('hello', now.subtract(const Duration(minutes: 5)), id: 1),
        _message('world', now, id: 2),
      ];

      final decoded = ChatHistoryService.decode(
        ChatHistoryService.encode(messages),
      );

      expect(decoded, hasLength(2));
      expect(decoded.first.message, 'hello');
      expect(decoded.last.timestamp, messages.last.timestamp);
      expect(decoded.last.fromClientId, 7);
    });

    test(
      'corrupt or truncated data yields an empty history, never a crash',
      () {
        // A tampered file must degrade gracefully: the alternative is an app
        // that cannot start a conversation any more.
        expect(ChatHistoryService.decode('not json at all'), isEmpty);
        expect(ChatHistoryService.decode('[{"ts":"nonsense"}]'), isEmpty);
        expect(ChatHistoryService.decode('[]'), isEmpty);
      },
    );

    test('entries without a usable timestamp are skipped', () {
      const raw =
          '[{"text":"orphan"},{"text":"kept","ts":"2026-08-23T10:00:00.000"}]';
      final decoded = ChatHistoryService.decode(raw);
      expect(decoded, hasLength(1));
      expect(decoded.single.message, 'kept');
    });
  });

  group('file naming', () {
    test('is scoped per server and safe for the platform', () {
      final name = ChatHistoryService.fileNameFor('AbC+/dEf=');
      // Base64 UIDs contain '+' and '/': the platform only accepts
      // alphanumerics, '_', '-' and '.'.
      expect(name, matches(r'^[A-Za-z0-9_\-.]+$'));
      expect(name.startsWith('chat_'), isTrue);
    });

    test('different servers get different files', () {
      expect(
        ChatHistoryService.fileNameFor('server-a'),
        isNot(ChatHistoryService.fileNameFor('server-b')),
      );
    });

    test('an empty uid still produces a valid name', () {
      final name = ChatHistoryService.fileNameFor('');
      expect(name, matches(r'^[A-Za-z0-9_\-.]+$'));
      expect(name.length, greaterThan(5));
    });
  });
}
