/// Direction of a TeamSpeak file transfer.
enum FileTransferDirection { upload, download }

/// Live state of one file transfer (upload or download), updated by the
/// engine's `file_transfer_progress` events and cleared on completion/failure.
class FileTransfer {
  final int transferId;
  final String remotePath;
  final String localPath;
  final int bytes;
  final int totalBytes;
  final FileTransferDirection direction;

  /// True once the engine reported a final result (success or failure).
  final bool done;
  final bool ok;
  final String? error;

  const FileTransfer({
    required this.transferId,
    required this.remotePath,
    this.localPath = '',
    this.bytes = 0,
    this.totalBytes = 0,
    this.direction = FileTransferDirection.upload,
    this.done = false,
    this.ok = false,
    this.error,
  });

  /// 0..1 fraction complete, clamped.
  double get progress =>
      totalBytes <= 0 ? 0 : (bytes / totalBytes).clamp(0.0, 1.0);

  FileTransfer copyWith({
    String? localPath,
    int? bytes,
    int? totalBytes,
    bool? done,
    bool? ok,
    Object? error = _sentinel,
  }) => FileTransfer(
    transferId: transferId,
    remotePath: remotePath,
    localPath: localPath ?? this.localPath,
    bytes: bytes ?? this.bytes,
    totalBytes: totalBytes ?? this.totalBytes,
    direction: direction,
    done: done ?? this.done,
    ok: ok ?? this.ok,
    error: error == _sentinel ? this.error : error as String?,
  );
}

const _sentinel = Object();
