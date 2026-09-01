import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/channel.dart';
import 'package:NEk0/models/client.dart';
import 'package:NEk0/models/ts_state.dart';

void main() {
  group('TsChannel metadata', () {
    test('parses the rich channel fields from JSON', () {
      final channel = TsChannel.fromJson({
        'id': 4,
        'name': 'Lobby',
        'parent_id': 0,
        'topic': 'Everyone',
        'has_password': true,
        'client_count': 3,
        'order': 1,
        'needed_talk_power': 50,
        'max_clients': -1,
        'codec': 4,
        'codec_quality': 7,
        'channel_type': 1,
        'is_default': true,
        'is_private': false,
        'subscribed': true,
        'icon_id': 128,
        'is_unencrypted': true,
      });

      expect(channel.neededTalkPower, 50);
      expect(channel.maxClients, -1);
      expect(channel.isUnlimitedClients, isTrue);
      expect(channel.codec, 4);
      expect(channel.isPermanent, isTrue);
      expect(channel.isSemiPermanent, isFalse);
      expect(channel.isDefault, isTrue);
      expect(channel.iconId, 128);
      expect(channel.subscribed, isTrue);
    });

    test('maps the channel-type codes to persistence flags', () {
      TsChannel ofType(int channelType) =>
          TsChannel(id: 1, name: 'A', parentId: 0, channelType: channelType);
      expect(ofType(0).isPermanent, isFalse);
      expect(ofType(0).isSemiPermanent, isFalse);
      expect(ofType(1).isPermanent, isTrue);
      expect(ofType(2).isSemiPermanent, isTrue);
    });
  });

  group('TsConnectionState.canTalkInCurrentChannel', () {
    TsConnectionState state({
      required int neededTalkPower,
      required int selfTalkPower,
      required bool grant,
    }) {
      return TsConnectionState(
        connectionId: 1,
        connected: true,
        ownClientId: 10,
        selectedChannelId: 2,
        channels: [
          const TsChannel(id: 1, name: 'A', parentId: 0),
          // The selected channel; neededTalkPower is applied below.
          TsChannel(
            id: 2,
            name: 'B',
            parentId: 0,
            neededTalkPower: neededTalkPower,
          ),
        ],
        clients: [
          TsClient(
            id: 10,
            nickname: 'me',
            channelId: 2,
            talkPower: selfTalkPower,
            talkPowerGranted: grant,
          ),
        ],
      );
    }

    test('is true when the channel has no talk-power requirement', () {
      final st = state(neededTalkPower: 0, selfTalkPower: 0, grant: false);
      expect(st.canTalkInCurrentChannel, isTrue);
    });

    test('is true when the grant covers the requirement', () {
      final st = state(neededTalkPower: 50, selfTalkPower: 50, grant: true);
      expect(st.canTalkInCurrentChannel, isTrue);
    });

    test('is false when the user lacks the required talk power', () {
      final st = state(neededTalkPower: 50, selfTalkPower: 10, grant: false);
      expect(st.canTalkInCurrentChannel, isFalse);
    });

    test('is true when the user is granted talk power explicitly', () {
      final st = state(neededTalkPower: 60, selfTalkPower: 5, grant: true);
      expect(st.canTalkInCurrentChannel, isTrue);
    });
  });
}
