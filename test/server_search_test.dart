import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/channel.dart';
import 'package:NEk0/models/client.dart';
import 'package:NEk0/models/server_file.dart';
import 'package:NEk0/models/server_search.dart';

void main() {
  group('searchServer', () {
    test('returns no hits for an empty or whitespace query', () {
      final hits = searchServer(
        '   ',
        channels: const [TsChannel(id: 1, name: 'Lobby', parentId: 0)],
        clients: const [],
        files: const [],
      );
      expect(hits.isEmpty, isTrue);
    });

    test('matches channels, clients and files case-insensitively', () {
      final hits = searchServer(
        'GAM',
        channels: const [
          TsChannel(id: 1, name: 'Gaming', parentId: 0),
          TsChannel(id: 2, name: 'Lobby', parentId: 0),
        ],
        clients: [const TsClient(id: 10, nickname: 'GamerX', channelId: 1)],
        files: const [ServerFile(name: 'game_notes.txt', size: 10)],
      );
      expect(hits.channels.map((c) => c.name), ['Gaming']);
      expect(hits.clients.map((c) => c.nickname), ['GamerX']);
      expect(hits.files.map((f) => f.name), ['game_notes.txt']);
    });

    test('a non-matching query yields no hits', () {
      final hits = searchServer(
        'zzz',
        channels: const [TsChannel(id: 1, name: 'Lobby', parentId: 0)],
        clients: const [],
        files: const [],
      );
      expect(hits.isEmpty, isTrue);
    });
  });

  group('channelPath', () {
    test('resolves a nested channel to Parent › Child, root-first', () {
      final channels = const [
        TsChannel(id: 1, name: 'Root', parentId: 0),
        TsChannel(id: 2, name: 'Mid', parentId: 1),
        TsChannel(id: 3, name: 'Leaf', parentId: 2),
      ];
      expect(channelPath(channels, 3), 'Root › Mid › Leaf');
      expect(channelPath(channels, 1), 'Root');
      expect(channelPath(channels, 0), '');
      expect(channelPath(channels, 999), '');
    });
  });
}
