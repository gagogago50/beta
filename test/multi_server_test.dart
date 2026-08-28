import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/ts_state.dart';

void main() {
  group('MultiServerState', () {
    test('starts empty', () {
      const s = MultiServerState();
      expect(s.sessions, isEmpty);
      expect(s.order, isEmpty);
      expect(s.selectedId, isNull);
      expect(s.hasAnyConnected, isFalse);
      expect(s.connectedCount, 0);
    });

    test('copyWith replaces sessions and order', () {
      const s = MultiServerState();
      final c1 = const TsConnectionState(connectionId: 1, connected: true);
      final up = s.copyWith(sessions: {1: c1}, order: const [1], selectedId: 1);
      expect(up.sessions[1]?.connected, isTrue);
      expect(up.order, [1]);
      expect(up.selectedId, 1);
      expect(up.hasAnyConnected, isTrue);
      expect(up.connectedCount, 1);
    });

    test('selected falls back to an empty state when no session', () {
      const s = MultiServerState();
      expect(s.selected.connected, isFalse);
      expect(s.selected.connectionId, 0);
    });

    test('selected returns the focused session', () {
      const s = MultiServerState(
        sessions: {5: TsConnectionState(connectionId: 5, connected: true)},
        order: [5],
        selectedId: 5,
      );
      expect(s.selected.connectionId, 5);
      expect(s.selected.connected, isTrue);
    });

    test('connectionId is copied through copyWith', () {
      const base = TsConnectionState(connectionId: 7, connected: true);
      final next = base.copyWith(inputMuted: true);
      expect(next.connectionId, 7);
      expect(next.connected, isTrue);
      expect(next.inputMuted, isTrue);
    });

    test('channel comfort fields default to off/empty', () {
      const s = TsConnectionState();
      expect(s.favoriteChannelIds, isEmpty);
      expect(s.channelsSortedAlpha, isFalse);
      expect(s.eventSoundsEnabled, isFalse);
    });

    test('channel comfort fields survive copyWith', () {
      const base = TsConnectionState(connectionId: 9);
      final next = base.copyWith(
        favoriteChannelIds: const {3, 11},
        channelsSortedAlpha: true,
        eventSoundsEnabled: true,
      );
      expect(next.favoriteChannelIds, {3, 11});
      expect(next.channelsSortedAlpha, isTrue);
      expect(next.eventSoundsEnabled, isTrue);
    });

    test('labels are looked up with a default', () {
      const s = MultiServerState(labels: {1: 'Alpha'});
      expect(s.labelFor(1), 'Alpha');
      expect(s.labelFor(2), 'server');
    });

    test('labels are copied through copyWith', () {
      const s = MultiServerState();
      final up = s.copyWith(labels: {1: 'Alpha'});
      expect(up.labels[1], 'Alpha');
      // A copyWithout touches nothing else.
      expect(up.sessions, isEmpty);
    });
  });
}
