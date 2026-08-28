import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/client.dart';
import 'package:NEk0/models/server.dart';
import 'package:NEk0/models/ts_state.dart';

void main() {
  test('server bookmark serialization never contains passwords', () {
    final server = Server(
      id: 'server-1',
      name: 'Private server',
      address: 'ts.example.test',
      nickname: 'User',
      channel: 'Encrypted',
      password: 'server-secret',
      channelPassword: 'channel-secret',
    );

    final json = server.toJson();

    expect(json['password'], isNull);
    expect(json['channel_password'], isNull);
    expect(json.values, isNot(contains('server-secret')));
    expect(json.values, isNot(contains('channel-secret')));
  });

  test('client group information is parsed from the Rust snapshot', () {
    final client = TsClient.fromJson({
      'id': 7,
      'nickname': 'Admin',
      'channel_id': 3,
      'channel_group_id': 8,
      'channel_group_name': 'Channel Admin',
      'server_group_ids': [6, 9],
      'server_group_names': ['Server Admin', 'Moderator'],
      'is_whispering': true,
    });

    expect(client.channelGroupId, 8);
    expect(client.channelGroupName, 'Channel Admin');
    expect(client.serverGroupIds, [6, 9]);
    expect(client.serverGroupNames, ['Server Admin', 'Moderator']);
    expect(client.isWhispering, isTrue);
  });

  test('whisper is only considered armable once a target exists', () {
    const empty = TsConnectionState();
    expect(empty.hasWhisperTargets, isFalse);

    final withClient = empty.copyWith(whisperTargetClientIds: const [12]);
    expect(withClient.hasWhisperTargets, isTrue);
    expect(withClient.whisperTargetChannelIds, isEmpty);

    final withChannel = empty.copyWith(whisperTargetChannelIds: const [3]);
    expect(withChannel.hasWhisperTargets, isTrue);
  });

  test('whisper allow list survives an unrelated state update', () {
    const base = TsConnectionState(
      whisperAllowlistEnabled: true,
      whisperAllowedUids: ['uid-a', 'uid-b'],
    );

    final updated = base.copyWith(rttMs: 42);

    expect(updated.whisperAllowlistEnabled, isTrue);
    expect(updated.whisperAllowedUids, ['uid-a', 'uid-b']);
  });

  test('command throttling is informational, never an error', () {
    const base = TsConnectionState(connected: true);

    final throttled = base.copyWith(
      pendingCommands: 4,
      commandRateDegraded: true,
    );

    expect(throttled.pendingCommands, 4);
    expect(throttled.commandRateDegraded, isTrue);
    // A backlog must not look like a failure to the rest of the app.
    expect(throttled.error, isNull);
    expect(throttled.connected, isTrue);
  });

  test('clearing away also clears the reason', () {
    const away = TsConnectionState(
      connected: true,
      away: true,
      awayMessage: 'back in 5',
    );

    // The notifier clears both at once; copyWith must be able to express it.
    final back = away.copyWith(away: false, awayMessage: null);

    expect(back.away, isFalse);
    expect(back.awayMessage, isNull);
    // An unrelated update keeps the reason intact.
    expect(away.copyWith(rttMs: 12).awayMessage, 'back in 5');
  });
}
