/// One entry of a channel file listing, as returned by the engine's
/// `file_list` event (a `ftgetfilelist` reply).
class ServerFile {
  final String name;
  final int size;
  final int modified;
  final bool isDirectory;

  const ServerFile({
    required this.name,
    required this.size,
    this.modified = 0,
    this.isDirectory = false,
  });

  factory ServerFile.fromJson(Map<String, dynamic> json) => ServerFile(
    name: json['name'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
    modified: (json['modified'] as num?)?.toInt() ?? 0,
    isDirectory: json['is_directory'] as bool? ?? false,
  );

  /// Whether the name ends with '/', which a directory may also signal.
  bool get looksLikeDirectory => isDirectory;

  /// Human-readable size (B / KiB / MiB / GiB).
  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KiB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MiB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
  }
}
