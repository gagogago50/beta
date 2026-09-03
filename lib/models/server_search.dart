import 'channel.dart';
import 'client.dart';
import 'server_file.dart';

/// Pure search over one server's channels, clients and files.
///
/// Kept separate from the widget so the matching/filtering logic can be unit
/// tested and reused by the global search sheet and any future entry point.
class ServerSearchHits {
  final List<TsChannel> channels;
  final List<TsClient> clients;
  final List<ServerFile> files;

  const ServerSearchHits({
    this.channels = const [],
    this.clients = const [],
    this.files = const [],
  });

  bool get isEmpty => channels.isEmpty && clients.isEmpty && files.isEmpty;
}

/// Filters [channels], [clients] and [files] by a case-insensitive substring
/// match on their name. An empty [query] returns an empty hit set (the caller
/// decides how to render no-query state).
ServerSearchHits searchServer(
  String query, {
  required List<TsChannel> channels,
  required List<TsClient> clients,
  required List<ServerFile> files,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const ServerSearchHits();

  return ServerSearchHits(
    channels: channels
        .where((c) => c.name.toLowerCase().contains(q))
        .toList(growable: false),
    clients: clients
        .where((c) => c.nickname.toLowerCase().contains(q))
        .toList(growable: false),
    files: files
        .where((f) => f.name.toLowerCase().contains(q))
        .toList(growable: false),
  );
}

/// Builds the display path of a channel (Parent › Child), root-first.
String channelPath(List<TsChannel> channels, int channelId) {
  if (channelId == 0) return '';
  final channel = channels.where((c) => c.id == channelId).firstOrNull;
  if (channel == null) return '';
  final parent = channelPath(channels, channel.parentId);
  return parent.isEmpty ? channel.name : '$parent › ${channel.name}';
}
