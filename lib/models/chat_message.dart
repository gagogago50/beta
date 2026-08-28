/// Where a message belongs.
///
/// TeamSpeak's `targetmode` alone is not enough: two private messages with
/// different peers share `targetmode = 1`, so the peer is part of the identity
/// of a private thread.
class ChatThreadKey {
  /// `channel`, `server`, or `client:<peer id>`.
  final String value;

  const ChatThreadKey(this.value);

  static const channel = ChatThreadKey('channel');
  static const server = ChatThreadKey('server');

  static ChatThreadKey privateWith(int peerId) =>
      ChatThreadKey('client:$peerId');

  bool get isPrivate => value.startsWith('client:');

  /// Peer id of a private thread, null for channel/server threads.
  int? get peerId =>
      isPrivate ? int.tryParse(value.substring('client:'.length)) : null;

  @override
  bool operator ==(Object other) =>
      other is ChatThreadKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

class ChatMessage {
  final int id;
  final String fromClient;
  final int fromClientId;
  final int targetMode; // 1=private, 2=channel, 3=server
  final String message;
  final DateTime timestamp;

  /// The other party of a private conversation.
  ///
  /// For an incoming private message this is the sender; for one we send, the
  /// recipient. Without it an outgoing message would be filed under our own
  /// id and the two halves of the same conversation would end up in two
  /// different threads.
  final int? peerId;

  /// Display name of [peerId], captured when the message is created because a
  /// client can disconnect and disappear from the roster.
  final String? peerName;

  const ChatMessage({
    required this.id,
    required this.fromClient,
    required this.fromClientId,
    required this.targetMode,
    required this.message,
    required this.timestamp,
    this.peerId,
    this.peerName,
  });

  /// Thread this message belongs to.
  ///
  /// A private message without a known peer falls back to the sender, which is
  /// correct for anything received and for histories written before the peer
  /// was recorded.
  ChatThreadKey get threadKey => switch (targetMode) {
    1 => ChatThreadKey.privateWith(peerId ?? fromClientId),
    3 => ChatThreadKey.server,
    _ => ChatThreadKey.channel,
  };
}

/// A conversation, built from the flat message list.
class ChatThread {
  final ChatThreadKey key;

  /// Peer name for private threads; channel/server threads use a localized
  /// label chosen by the UI.
  final String? title;
  final List<ChatMessage> messages;
  final int unread;

  const ChatThread({
    required this.key,
    required this.messages,
    this.title,
    this.unread = 0,
  });

  ChatMessage? get last => messages.isEmpty ? null : messages.last;

  /// Groups a flat message list into threads, most recently active first,
  /// with channel and server pinned at the front so their position never
  /// jumps under the user's finger.
  static List<ChatThread> group(
    List<ChatMessage> messages, {
    Map<String, int> unreadByThread = const {},
  }) {
    final byKey = <String, List<ChatMessage>>{};
    final names = <String, String>{};
    for (final message in messages) {
      final key = message.threadKey;
      byKey.putIfAbsent(key.value, () => []).add(message);
      if (key.isPrivate) {
        // Prefer an explicit peer name, fall back to the sender's name.
        final name = message.peerName ?? message.fromClient;
        if (name.isNotEmpty) names[key.value] = name;
      }
    }

    final privateKeys =
        byKey.keys.where((k) => k.startsWith('client:')).toList()
          ..sort((left, right) {
            final leftTime = byKey[left]!.last.timestamp;
            final rightTime = byKey[right]!.last.timestamp;
            return rightTime.compareTo(leftTime);
          });

    return [
      ChatThread(
        key: ChatThreadKey.channel,
        messages: byKey[ChatThreadKey.channel.value] ?? const [],
        unread: unreadByThread[ChatThreadKey.channel.value] ?? 0,
      ),
      ChatThread(
        key: ChatThreadKey.server,
        messages: byKey[ChatThreadKey.server.value] ?? const [],
        unread: unreadByThread[ChatThreadKey.server.value] ?? 0,
      ),
      for (final key in privateKeys)
        ChatThread(
          key: ChatThreadKey(key),
          title: names[key],
          messages: byKey[key]!,
          unread: unreadByThread[key] ?? 0,
        ),
    ];
  }
}
