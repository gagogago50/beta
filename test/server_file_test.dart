import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/server_file.dart';

void main() {
  group('ServerFile', () {
    test('parses the engine JSON fields', () {
      final file = ServerFile.fromJson({
        'name': 'notes.txt',
        'size': 2048,
        'modified': 1700000000,
        'is_directory': false,
      });
      expect(file.name, 'notes.txt');
      expect(file.size, 2048);
      expect(file.modified, 1700000000);
      expect(file.isDirectory, isFalse);
      expect(file.looksLikeDirectory, isFalse);
    });

    test('detects directories and reports human sizes', () {
      expect(
        ServerFile(name: 'pics', size: 0, isDirectory: true).isDirectory,
        isTrue,
      );
      expect(ServerFile(name: 'a', size: 500).sizeLabel, '500 B');
      expect(ServerFile(name: 'a', size: 2048).sizeLabel, '2.0 KiB');
      expect(ServerFile(name: 'a', size: 2 * 1024 * 1024).sizeLabel, '2.0 MiB');
      expect(
        ServerFile(name: 'a', size: 2 * 1024 * 1024 * 1024).sizeLabel,
        '2.0 GiB',
      );
    });
  });
}
