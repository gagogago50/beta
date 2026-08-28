import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import 'app_log.dart';
import 'secure_storage.dart';

/// How long a stored conversation is kept.
enum HistoryRetention {
  sevenDays(7),
  thirtyDays(30),
  ninetyDays(90);

  const HistoryRetention(this.days);

  final int days;

  static HistoryRetention fromDays(int days) => HistoryRetention.values
      .firstWhere((value) => value.days == days, orElse: () => thirtyDays);
}

/// Encrypted, opt-in chat history.
///
/// Three rules shape this file:
///
/// 1. **Opt-in.** Disabled by default: a voice client that silently records
///    every private conversation is a liability, not a feature.
/// 2. **Encrypted at rest.** The payload goes through the Keystore-backed file
///    storage, the same key that protects the TeamSpeak identity — plaintext
///    JSON in app storage would be readable from any device backup path.
/// 3. **Bounded.** Retention in days *and* a hard entry cap, so a busy server
///    cannot grow the file without limit.
class ChatHistoryService {
  static const _channel = MethodChannel('com.senlinjun.nek0/secure_storage');

  /// Maximum number of messages kept per server, newest first.
  static const maxEntriesPerServer = 500;

  const ChatHistoryService._();

  /// One file per server: histories must not leak between servers, and a
  /// single file would have to be rewritten entirely for every message.
  static String fileNameFor(String serverUid) {
    final safe = serverUid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    // Non-empty and bounded: the platform refuses anything else.
    final trimmed = safe.isEmpty ? 'unknown' : safe;
    return 'chat_${trimmed.substring(0, trimmed.length.clamp(0, 96))}.json';
  }

  /// Applies retention and the entry cap. Pure, so it is unit-testable
  /// without any platform channel.
  static List<ChatMessage> prune(
    List<ChatMessage> messages, {
    required HistoryRetention retention,
    DateTime? now,
  }) {
    final cutoff = (now ?? DateTime.now()).subtract(
      Duration(days: retention.days),
    );
    final kept = messages
        .where((message) => message.timestamp.isAfter(cutoff))
        .toList();
    if (kept.length <= maxEntriesPerServer) return kept;
    // Keep the most recent ones: an old message is what the user is least
    // likely to need.
    return kept.sublist(kept.length - maxEntriesPerServer);
  }

  static List<ChatMessage> decode(String raw) {
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((entry) => _messageFromJson(entry as Map<String, dynamic>))
          .whereType<ChatMessage>()
          .toList();
    } catch (error) {
      AppLog.w('history', 'unreadable history discarded');
      return const [];
    }
  }

  static String encode(List<ChatMessage> messages) => jsonEncode([
    for (final message in messages)
      {
        'id': message.id,
        'from': message.fromClient,
        'from_id': message.fromClientId,
        'target': message.targetMode,
        'text': message.message,
        'ts': message.timestamp.toIso8601String(),
        // Peer of a private conversation: without it a restored history would
        // merge every private thread into one.
        if (message.peerId != null) 'peer': message.peerId,
        if (message.peerName != null) 'peer_name': message.peerName,
      },
  ]);

  static ChatMessage? _messageFromJson(Map<String, dynamic> json) {
    final timestamp = DateTime.tryParse(json['ts'] as String? ?? '');
    if (timestamp == null) return null;
    return ChatMessage(
      id: json['id'] as int? ?? 0,
      fromClient: json['from'] as String? ?? '',
      fromClientId: json['from_id'] as int? ?? 0,
      targetMode: json['target'] as int? ?? 2,
      message: json['text'] as String? ?? '',
      timestamp: timestamp,
      peerId: json['peer'] as int?,
      peerName: json['peer_name'] as String?,
    );
  }

  /// Loads the stored conversation for [serverUid], already pruned.
  static Future<List<ChatMessage>> load(
    String serverUid, {
    required HistoryRetention retention,
  }) async {
    if (serverUid.isEmpty) return const [];
    try {
      final raw = await _channel.invokeMethod<String>('read_file', {
        'name': fileNameFor(serverUid),
      });
      if (raw == null || raw.isEmpty) return const [];
      return prune(decode(raw), retention: retention);
    } on PlatformException catch (error) {
      AppLog.w('history', 'load failed: ${error.code}');
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Persists [messages] (pruned first). Never throws: losing history is
  /// annoying, crashing the app over it is worse.
  static Future<void> save(
    String serverUid,
    List<ChatMessage> messages, {
    required HistoryRetention retention,
  }) async {
    if (serverUid.isEmpty) return;
    try {
      final pruned = prune(messages, retention: retention);
      await _channel.invokeMethod<bool>('write_file', {
        'name': fileNameFor(serverUid),
        'value': encode(pruned),
      });
    } on PlatformException catch (error) {
      AppLog.w('history', 'save failed: ${error.code}');
    } on MissingPluginException {
      // Non-Android host (tests).
    }
  }

  /// Deletes the history of one server.
  static Future<void> clear(String serverUid) async {
    if (serverUid.isEmpty) return;
    try {
      await _channel.invokeMethod<bool>('delete_file', {
        'name': fileNameFor(serverUid),
      });
    } on PlatformException catch (error) {
      AppLog.w('history', 'clear failed: ${error.code}');
    } on MissingPluginException {
      // Nothing to do.
    }
  }

  /// Deletes every stored history. Called by the "erase secrets" command and
  /// when the user turns the feature off.
  static Future<int> clearAll() async {
    try {
      final removed = await _channel.invokeMethod<int>('delete_all_files');
      return removed ?? 0;
    } on PlatformException catch (error) {
      AppLog.w('history', 'clearAll failed: ${error.code}');
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }
}

/// Kept so callers can reference the identity key alongside history files.
typedef SecureStorageKeys = SecureStorage;
