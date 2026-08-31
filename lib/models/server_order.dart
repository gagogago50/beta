import 'server.dart';

/// Pure helpers for ordering the server bookmark list. Kept free of any
/// platform dependency so they can be unit-tested directly.
///
/// * Pinned servers ([favoriteIds]) always sort first, in the order they were
///   pinned relative to the stored list.
/// * An explicit reorder ([move]) works on the stored (unpinned) list first,
///   then the favorites are re-floated to the front.
List<Server> sortServers(List<Server> servers, Set<String> favoriteIds) {
  return [
    ...servers.where((s) => favoriteIds.contains(s.id)),
    ...servers.where((s) => !favoriteIds.contains(s.id)),
  ];
}

/// Moves `serverId` by `delta` positions (+1 down, -1 up) within `servers` and
/// returns the reordered list with favorites floated to the front. Returns the
/// input unchanged when the move is out of range.
List<Server> moveServer(
  List<Server> servers,
  Set<String> favoriteIds,
  String serverId,
  int delta,
) {
  final list = [...servers];
  final idx = list.indexWhere((s) => s.id == serverId);
  final target = idx + delta;
  if (idx < 0 || target < 0 || target >= list.length) return servers;
  final item = list.removeAt(idx);
  list.insert(target, item);
  return sortServers(list, favoriteIds);
}
