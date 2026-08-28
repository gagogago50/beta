import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/file_transfer.dart';

void main() {
  group('FileTransfer', () {
    test('progress is clamped to 0..1', () {
      const none = FileTransfer(transferId: 1, remotePath: '/a', totalBytes: 0);
      expect(none.progress, 0);

      const part = FileTransfer(
        transferId: 1,
        remotePath: '/a',
        bytes: 500,
        totalBytes: 1000,
      );
      expect(part.progress, 0.5);

      const over = FileTransfer(
        transferId: 1,
        remotePath: '/a',
        bytes: 2000,
        totalBytes: 1000,
      );
      expect(over.progress, 1.0);
    });

    test('copyWith updates bytes but keeps direction', () {
      const t = FileTransfer(
        transferId: 7,
        remotePath: '/x',
        direction: FileTransferDirection.upload,
        bytes: 10,
        totalBytes: 100,
      );
      final next = t.copyWith(bytes: 50);
      expect(next.bytes, 50);
      expect(next.totalBytes, 100);
      expect(next.direction, FileTransferDirection.upload);
    });

    test('copyWith error is one-shot (can be cleared)', () {
      const t = FileTransfer(transferId: 7, remotePath: '/x', error: 'boo');
      expect(t.error, 'boo');
      final cleared = t.copyWith(error: null);
      expect(cleared.error, isNull);
    });

    test('a transfer starts incomplete and fails closed', () {
      const t = FileTransfer(transferId: 1, remotePath: '/a');
      expect(t.done, isFalse);
      expect(t.ok, isFalse);
      expect(t.progress, 0);
    });
  });
}
