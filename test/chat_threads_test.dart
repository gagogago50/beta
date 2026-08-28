import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/chat_message.dart';
import 'package:NEk0/services/chat_history_service.dart';

ChatMessage _msg({
  required int targetMode,
  required int fromId,
  String from = 'Someone',
  int? peerId,
  String? peerName,
  String text = 'hello',
  DateTime? at,
}) => ChatMessage(
  id: 0,
  fromClient: from,
  fromClientId: fromId,
  targetMode: targetMode,
  message: text,
  timestamp: at ?? DateTime(2026, 8, 23, 12),
  peerId: peerId,
  peerName: peerName,
);

void main() {
  group('thread routing', () {
    test('channel and server messages have their own threads', () {
      expect(_msg(targetMode: 2, fromId: 5).threadKey, ChatThreadKey.channel);
      expect(_msg(targetMode: 3, fromId: 5).threadKey, ChatThreadKey.server);
    });

    test('an incoming private message is filed under its sender', () {
      final message = _msg(targetMode: 1, fromId: 42, peerId: 42);
      expect(message.threadKey, ChatThreadKey.privateWith(42));
    });

    test('an outgoing private message is filed under the recipient', () {
      // Sent by us (id 1) to peer 42: both halves must share one thread,
      // otherwise a conversation is split in two.
      final outgoing = _msg(targetMode: 1, fromId: 1, peerId: 42);
      final incoming = _msg(targetMode: 1, fromId: 42, peerId: 42);
      expect(outgoing.threadKey, incoming.threadKey);
    });

    test(
      'a legacy private message without a peer falls back to the sender',
      () {
        // Histories written before the peer was recorded must still open.
        final legacy = _msg(targetMode: 1, fromId: 9);
        expect(legacy.threadKey, ChatThreadKey.privateWith(9));
      },
    );

    test('two peers never share a thread', () {
      expect(
        _msg(targetMode: 1, fromId: 1, peerId: 7).threadKey,
        isNot(_msg(targetMode: 1, fromId: 1, peerId: 8).threadKey),
      );
    });

    test('a private key exposes its peer id, others do not', () {
      expect(ChatThreadKey.privateWith(12).peerId, 12);
      expect(ChatThreadKey.channel.peerId, isNull);
      expect(ChatThreadKey.server.peerId, isNull);
    });
  });

  group('grouping', () {
    test('channel and server threads always exist, even empty', () {
      final threads = ChatThread.group(const []);
      expect(threads.map((t) => t.key), [
        ChatThreadKey.channel,
        ChatThreadKey.server,
      ]);
      expect(threads.first.messages, isEmpty);
    });

    test('private threads are ordered by most recent activity', () {
      final base = DateTime(2026, 8, 23, 12);
      final messages = [
        _msg(targetMode: 1, fromId: 7, peerId: 7, at: base),
        _msg(
          targetMode: 1,
          fromId: 8,
          peerId: 8,
          at: base.add(const Duration(minutes: 5)),
        ),
      ];

      final threads = ChatThread.group(messages);
      // Channel and server stay pinned first so tabs do not jump around.
      expect(threads[0].key, ChatThreadKey.channel);
      expect(threads[1].key, ChatThreadKey.server);
      expect(threads[2].key, ChatThreadKey.privateWith(8));
      expect(threads[3].key, ChatThreadKey.privateWith(7));
    });

    test('a private thread is titled with the peer name', () {
      final threads = ChatThread.group([
        _msg(targetMode: 1, fromId: 1, peerId: 7, peerName: 'Alice'),
      ]);
      final private = threads.firstWhere((t) => t.key.isPrivate);
      expect(private.title, 'Alice');
    });

    test('unread counters are attached to the right thread', () {
      final threads = ChatThread.group(
        [_msg(targetMode: 1, fromId: 7, peerId: 7)],
        unreadByThread: {'client:7': 3, 'channel': 1},
      );
      expect(
        threads.firstWhere((t) => t.key == ChatThreadKey.channel).unread,
        1,
      );
      expect(threads.firstWhere((t) => t.key.isPrivate).unread, 3);
    });

    test('messages keep their order inside a thread', () {
      final base = DateTime(2026, 8, 23, 12);
      final threads = ChatThread.group([
        _msg(targetMode: 2, fromId: 1, text: 'first', at: base),
        _msg(
          targetMode: 2,
          fromId: 1,
          text: 'second',
          at: base.add(const Duration(seconds: 30)),
        ),
      ]);
      final channel = threads.first;
      expect(channel.messages.map((m) => m.message), ['first', 'second']);
      expect(channel.last?.message, 'second');
    });
  });

  group('history persistence of threads', () {
    test('the peer survives a save/load round trip', () {
      final messages = [
        _msg(targetMode: 1, fromId: 1, peerId: 42, peerName: 'Bob'),
      ];

      final restored = ChatHistoryService.decode(
        ChatHistoryService.encode(messages),
      );

      expect(restored.single.peerId, 42);
      expect(restored.single.peerName, 'Bob');
      // Which is what puts it back in the same tab after a restart.
      expect(restored.single.threadKey, ChatThreadKey.privateWith(42));
    });

    test('channel messages carry no peer field', () {
      final encoded = ChatHistoryService.encode([
        _msg(targetMode: 2, fromId: 3),
      ]);
      expect(encoded.contains('"peer"'), isFalse);
    });
  });
}
