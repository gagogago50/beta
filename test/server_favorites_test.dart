import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/server.dart';
import 'package:NEk0/models/server_order.dart';
import 'package:NEk0/models/ts_state.dart';

void main() {
  Server mk(String id, String name) =>
      Server(id: id, name: name, address: '$id.example.com', nickname: 'user');

  group('sortServers', () {
    test('favorited servers sort first', () {
      final servers = [mk('b', 'Beta'), mk('a', 'Alpha'), mk('c', 'Gamma')];
      final sorted = sortServers(servers, {'b'});
      expect(sorted.map((s) => s.id).toList(), ['b', 'a', 'c']);
    });

    test('no favorites keeps order', () {
      final servers = [mk('a', 'Alpha'), mk('b', 'Beta')];
      expect(sortServers(servers, {}).map((s) => s.id).toList(), ['a', 'b']);
    });
  });

  group('moveServer', () {
    test('moves up and refloats favorites', () {
      final servers = [mk('a', 'A'), mk('b', 'B'), mk('c', 'C')];
      final moved = moveServer(servers, {}, 'c', -1);
      expect(moved.map((s) => s.id).toList(), ['a', 'c', 'b']);
      // Favorite stays at the front even after a manual move.
      final favMoved = moveServer(servers, {'b'}, 'c', -1);
      expect(favMoved.map((s) => s.id).toList(), ['b', 'a', 'c']);
    });

    test('edge moves are no-ops', () {
      final servers = [mk('a', 'A'), mk('b', 'B')];
      expect(moveServer(servers, {}, 'a', -1).map((s) => s.id).toList(), [
        'a',
        'b',
      ]);
      expect(moveServer(servers, {}, 'b', 1).map((s) => s.id).toList(), [
        'a',
        'b',
      ]);
      // Unknown id is a no-op too.
      expect(moveServer(servers, {}, 'zzz', 1).map((s) => s.id).toList(), [
        'a',
        'b',
      ]);
    });
  });

  group('ServerListState favorites', () {
    test('favoriteIds persist via copyWith', () {
      const s = ServerListState();
      final up = s.copyWith(favoriteIds: const {'x'});
      expect(up.favoriteIds, {'x'});
      expect(up.servers, isEmpty);
    });
  });
}
