import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/resume_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ResumeIntent', () {
    test('requires address and nickname', () {
      const full = ResumeIntent(
        address: 'voice.teamspeak.com',
        nickname: 'Bob',
      );
      expect(full.hasCredentials, isTrue);
      const empty = ResumeIntent(address: '', nickname: '');
      expect(empty.hasCredentials, isFalse);
    });

    test('mic is muted by default (safety)', () {
      const i = ResumeIntent(address: 'a', nickname: 'b');
      expect(i.micWasMuted, isTrue);
    });
  });

  group('ResumeIntentStore', () {
    test('round-trips a stored intent', () async {
      await ResumeIntentStore.save(
        const ResumeIntent(
          address: 'voice.teamspeak.com',
          nickname: 'Bob',
          channel: 'Lobby',
          micWasMuted: false,
        ),
      );
      final loaded = await ResumeIntentStore.load();
      expect(loaded, isNotNull);
      expect(loaded!.address, 'voice.teamspeak.com');
      expect(loaded.nickname, 'Bob');
      expect(loaded.channel, 'Lobby');
      expect(loaded.micWasMuted, isFalse);
    });

    test('load returns null when nothing stored', () async {
      expect(await ResumeIntentStore.load(), isNull);
    });

    test('clear removes the intent', () async {
      await ResumeIntentStore.save(
        const ResumeIntent(address: 'a', nickname: 'b'),
      );
      await ResumeIntentStore.clear();
      expect(await ResumeIntentStore.load(), isNull);
    });

    test('a truncated stored value is treated as absent', () async {
      await ResumeIntentStore.save(
        const ResumeIntent(address: 'a', nickname: 'b'),
      );
      final prefs = await SharedPreferences.getInstance();
      // Simulate a corrupt/truncated raw value.
      await prefs.setString('resume_intent', 'only-address');
      expect(await ResumeIntentStore.load(), isNull);
    });
  });
}
