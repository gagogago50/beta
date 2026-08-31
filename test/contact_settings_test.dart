import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/contact_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('preferredDisplayName', () {
    const base = ContactSettings(serverUid: 's', uid: 'u');
    test('mode 2 (default) uses the server nickname', () {
      expect(base.preferredDisplayName('Alice'), 'Alice');
    });

    test('mode 1 uses only the custom name', () {
      final c = base.copyWith(customName: 'Bob', displayMode: 1);
      expect(c.preferredDisplayName('Alice'), 'Bob');
    });

    test('mode 0 prefixes the nickname with [customName]', () {
      final c = base.copyWith(customName: 'Bob', displayMode: 0);
      expect(c.preferredDisplayName('Alice'), '[Bob] Alice');
    });

    test('falls back to the uid when no nickname', () {
      expect(base.copyWith(displayMode: 2).preferredDisplayName(''), 'u');
    });
  });

  group('ContactStore round-trip', () {
    test('save + load a contact', () async {
      await ContactStore.save(
        ContactSettings(
          serverUid: 'sv',
          uid: 'uid1',
          customName: 'Nom',
          displayMode: 1,
          muted: true,
          ignorePokes: true,
          allowWhispers: true,
        ),
      );
      final loaded = await ContactStore.load('sv', 'uid1');
      expect(loaded, isNotNull);
      expect(loaded!.customName, 'Nom');
      expect(loaded.displayMode, 1);
      expect(loaded.muted, isTrue);
      expect(loaded.ignorePokes, isTrue);
      expect(loaded.allowWhispers, isTrue);
    });

    test('load returns null when absent', () async {
      expect(await ContactStore.load('sv', 'missing'), isNull);
    });

    test('remove deletes the contact', () async {
      await ContactStore.save(const ContactSettings(serverUid: 'sv', uid: 'u'));
      await ContactStore.remove('sv', 'u');
      expect(await ContactStore.load('sv', 'u'), isNull);
    });

    test('uniqueIdentifier strips apostrophes (Windows behaviour)', () {
      final c = const ContactSettings(serverUid: 'sv', uid: "a'b");
      expect(c.uid, "a'b");
    });

    test('forServer lists only that server\'s contacts', () async {
      await ContactStore.save(const ContactSettings(serverUid: 'sA', uid: '1'));
      await ContactStore.save(const ContactSettings(serverUid: 'sA', uid: '2'));
      await ContactStore.save(const ContactSettings(serverUid: 'sB', uid: '1'));
      final a = await ContactStore.forServer('sA');
      expect(a.length, 2);
      expect(a.map((c) => c.uid), ['1', '2']);
    });
  });
}
