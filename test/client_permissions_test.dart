import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/client.dart';
import 'package:NEk0/models/client_permissions.dart';

void main() {
  group('ClientPermissions', () {
    test('nothing is allowed before the server sends a hint', () {
      // Denying by default is the whole point: assuming permission would show
      // actions that fail a second later.
      const none = ClientPermissions.none;
      expect(none.canKickFromChannel, isFalse);
      expect(none.canKickFromServer, isFalse);
      expect(none.canBan, isFalse);
      expect(none.canMove, isFalse);
      expect(none.canPoke, isFalse);
      expect(none.hasAnyModeration, isFalse);
    });

    test('decodes each protocol flag independently', () {
      // Values mirror ClientPermissionHint in the protocol declarations.
      expect(const ClientPermissions(1).canKickFromServer, isTrue);
      expect(const ClientPermissions(1).canKickFromChannel, isFalse);
      expect(const ClientPermissions(2).canKickFromChannel, isTrue);
      expect(const ClientPermissions(4).canBan, isTrue);
      expect(const ClientPermissions(8).canMove, isTrue);
      expect(const ClientPermissions(16).canPrivateMessage, isTrue);
      expect(const ClientPermissions(32).canPoke, isTrue);
      expect(const ClientPermissions(64).canWhisper, isTrue);
      expect(const ClientPermissions(128).canComplain, isTrue);
      expect(const ClientPermissions(256).canModifyPermissions, isTrue);
    });

    test('combines flags', () {
      const both = ClientPermissions(2 | 32); // kick channel + poke
      expect(both.canKickFromChannel, isTrue);
      expect(both.canPoke, isTrue);
      expect(both.canBan, isFalse);
      expect(both.hasAnyModeration, isTrue);
    });

    test('hasAnyModeration ignores non-moderation flags', () {
      // Being allowed to whisper or write is not a moderation action and must
      // not make the moderation menu appear.
      const chatOnly = ClientPermissions(16 | 64 | 128);
      expect(chatOnly.canPrivateMessage, isTrue);
      expect(chatOnly.hasAnyModeration, isFalse);
    });

    test('unknown future bits do not crash or grant anything', () {
      const future = ClientPermissions(1 << 40);
      expect(future.hasAnyModeration, isFalse);
      expect(future.canBan, isFalse);
    });
  });

  group('TsClient permission parsing', () {
    test('reads permission_hints from the engine snapshot', () {
      final client = TsClient.fromJson({
        'id': 12,
        'nickname': 'Someone',
        'channel_id': 3,
        'permission_hints': 2 | 4,
      });

      expect(client.permissions.canKickFromChannel, isTrue);
      expect(client.permissions.canBan, isTrue);
      expect(client.permissions.canKickFromServer, isFalse);
    });

    test('a snapshot without hints denies everything', () {
      final client = TsClient.fromJson({
        'id': 12,
        'nickname': 'Someone',
        'channel_id': 3,
      });

      expect(client.permissions, ClientPermissions.none);
      expect(client.permissions.hasAnyModeration, isFalse);
    });

    test('copyWith keeps the permissions', () {
      final client = TsClient.fromJson({
        'id': 12,
        'nickname': 'Someone',
        'channel_id': 3,
        'permission_hints': 8,
      });

      expect(client.copyWith(isTalking: true).permissions.canMove, isTrue);
    });
  });

  group('TsClient group icons', () {
    test('parses channel and server group icons', () {
      final client = TsClient.fromJson({
        'id': 1,
        'nickname': 'Someone',
        'channel_id': 2,
        'channel_group_icon_id': 100,
        'server_group_names': ['Admin', 'Moderator'],
        'server_group_icon_ids': [200, 0],
      });

      expect(client.channelGroupIconId, 100);
      expect(client.serverGroupIconIds, [200, 0]);
      // Zero means "no icon" and must not be requested from the server.
      expect(client.groupIconIds, [100, 200]);
    });

    test('a client without icons asks for nothing', () {
      final client = TsClient.fromJson({
        'id': 1,
        'nickname': 'Someone',
        'channel_id': 2,
        'server_group_names': ['Guest'],
      });

      expect(client.groupIconIds, isEmpty);
    });

    test('channel group icon comes first', () {
      final client = TsClient.fromJson({
        'id': 1,
        'nickname': 'Someone',
        'channel_id': 2,
        'channel_group_icon_id': 7,
        'server_group_icon_ids': [8, 9],
      });

      expect(client.groupIconIds.first, 7);
      expect(client.groupIconIds, [7, 8, 9]);
    });

    test('copyWith keeps the icons', () {
      final client = TsClient.fromJson({
        'id': 1,
        'nickname': 'Someone',
        'channel_id': 2,
        'channel_group_icon_id': 5,
        'server_group_icon_ids': [6],
      });

      final talking = client.copyWith(isTalking: true);
      expect(talking.groupIconIds, [5, 6]);
    });
  });
}
