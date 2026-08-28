import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'app_log.dart';
import 'ts_ffi.dart';

/// Downloads and caches server icons through the TeamSpeak file-transfer
/// channel.
///
/// Icons live at `/icon_<id>` in channel 0 and are a few kilobytes at most.
/// The cache is keyed by `serverUid/iconId` because icon IDs are only unique
/// within one virtual server. In multi-server mode the *connection* used to
/// download is passed with each request, and in-flight deduplication is scoped
/// by server, so two servers sharing an icon id never collide.
class IconCache {
  static const _channel = MethodChannel('com.senlinjun.nek0/audio');

  /// Hard ceiling per icon. Real icons are < 100 kB; anything bigger is
  /// refused rather than cached.
  static const maxIconBytes = 512 * 1024;

  /// How long a cached icon is trusted before being fetched again.
  static const maxAge = Duration(days: 30);

  static String? _cacheRoot;

  /// Transfers in flight, scoped by server, so the same icon on the same server
  /// is never requested twice.
  static final Map<String, Completer<File?>> _inFlight = {};

  /// Icons the server refused or that failed: not retried for the session, to
  /// avoid hammering the file-transfer port on every roster refresh.
  static final Set<String> _failed = {};

  IconCache._();

  /// Android's private cache directory. Asking the platform avoids building a
  /// path by hand, which is exactly what the engine refuses.
  static Future<String?> _root() async {
    if (_cacheRoot != null) return _cacheRoot;
    try {
      final path = await _channel.invokeMethod<String>('cache_dir');
      if (path == null || path.isEmpty) return null;
      final dir = Directory('$path/icons');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _cacheRoot = dir.path;
      return _cacheRoot;
    } on PlatformException catch (error) {
      AppLog.w('icons', 'cache_dir failed: ${error.code}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static String _fileName(String serverUid, int iconId) {
    // The UID is base64 and can contain '/' and '+': keep only characters that
    // are safe in a file name.
    final safeUid = serverUid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '${safeUid}_$iconId';
  }

  static String _key(String serverUid, String id) => '$serverUid\u0000$id';

  /// TeamSpeak stores avatars as `/avatar_<client uid>` in channel 0.
  ///
  /// Avatars are user-supplied images: the size cap matters more here than for
  /// icons, and a failure must be as invisible as a missing icon.
  static const maxAvatarBytes = 1024 * 1024;

  static final Map<String, Completer<File?>> _avatarsInFlight = {};
  static final Set<String> _avatarFailures = {};
  static final Map<int, _PendingAvatar> _pendingAvatars = {};

  /// Cached avatar of the client identified by [clientUid], downloaded on
  /// demand. Null means "no avatar" — callers fall back to an initial or an
  /// icon, never to a broken image.
  ///
  /// [connectionId] is the session to download through; only the empty-UID
  /// short-circuit works without one.
  static Future<File?> avatar(
    String serverUid,
    String clientUid, {
    int connectionId = 0,
  }) async {
    if (clientUid.isEmpty) return null;
    final scopeKey = _key(serverUid, clientUid);
    if (_avatarFailures.contains(scopeKey)) return null;

    final root = await _root();
    if (root == null) return null;

    final safeClient = clientUid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final safeServer = serverUid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('$root/avatar_${safeServer}_$safeClient');
    if (file.existsSync()) {
      final age = DateTime.now().difference(file.lastModifiedSync());
      if (age < maxAge && file.lengthSync() > 0) return file;
    }

    final existing = _avatarsInFlight[scopeKey];
    if (existing != null) return existing.future;
    final completer = Completer<File?>();
    _avatarsInFlight[scopeKey] = completer;

    final transferId = TsNative.downloadFile(
      connectionId: connectionId,
      channelId: 0,
      // The path uses the raw base64 UID, exactly as the server stores it.
      remotePath: '/avatar_$clientUid',
      targetPath: file.path,
      maxBytes: maxAvatarBytes,
    );
    if (transferId == 0) {
      _avatarFailures.add(scopeKey);
      _avatarsInFlight.remove(scopeKey);
      completer.complete(null);
      return null;
    }
    _pendingAvatars[transferId] = _PendingAvatar(scopeKey, file, completer);
    return completer.future;
  }

  /// Returns the cached file for [iconId] on [serverUid], downloading it if
  /// needed. Returns null when the icon is unavailable — callers fall back to
  /// text.
  static Future<File?> get(
    String serverUid,
    int iconId, {
    int connectionId = 0,
  }) async {
    if (iconId == 0) return null;
    final scopeKey = _key(serverUid, '$iconId');
    if (_failed.contains(scopeKey)) return null;

    final root = await _root();
    if (root == null) return null;

    final file = File('$root/${_fileName(serverUid, iconId)}');
    if (file.existsSync()) {
      final age = DateTime.now().difference(file.lastModifiedSync());
      if (age < maxAge && file.lengthSync() > 0) return file;
    }

    // Coalesce concurrent requests for the same icon on the same server.
    final existing = _inFlight[scopeKey];
    if (existing != null) return existing.future;
    final completer = Completer<File?>();
    _inFlight[scopeKey] = completer;

    // TeamSpeak stores icons as unsigned 32-bit ids; the path uses the
    // unsigned representation.
    final unsigned = iconId < 0 ? iconId + 4294967296 : iconId;
    final transferId = TsNative.downloadFile(
      connectionId: connectionId,
      channelId: 0,
      remotePath: '/icon_$unsigned',
      targetPath: file.path,
      maxBytes: maxIconBytes,
    );
    if (transferId == 0) {
      _failed.add(scopeKey);
      _inFlight.remove(scopeKey);
      completer.complete(null);
      return null;
    }

    _pending[transferId] = _PendingIcon(scopeKey, file, completer);
    return completer.future;
  }

  static final Map<int, _PendingIcon> _pending = {};

  /// Called by the state notifier when the engine reports a transfer result.
  static void onTransferEvent({
    required int transferId,
    required bool ok,
    required String localPath,
  }) {
    final avatar = _pendingAvatars.remove(transferId);
    if (avatar != null) {
      _avatarsInFlight.remove(avatar.scopeKey);
      if (!ok || localPath.isEmpty) {
        // Most clients simply have no avatar: remember it so the roster does
        // not re-ask on every refresh.
        _avatarFailures.add(avatar.scopeKey);
        avatar.completer.complete(null);
      } else {
        avatar.completer.complete(avatar.file);
      }
      return;
    }
    final pending = _pending.remove(transferId);
    if (pending == null) return;
    _inFlight.remove(pending.scopeKey);
    if (!ok || localPath.isEmpty) {
      _failed.add(pending.scopeKey);
      pending.completer.complete(null);
      return;
    }
    pending.completer.complete(pending.file);
  }

  /// Forgets in-session failures (called on connect: a different server has
  /// different icons, and permissions may have changed).
  static void reset() {
    _failed.clear();
    _avatarFailures.clear();
    for (final pending in _pendingAvatars.values) {
      pending.completer.complete(null);
    }
    _pendingAvatars.clear();
    _avatarsInFlight.clear();
    for (final pending in _pending.values) {
      pending.completer.complete(null);
    }
    _pending.clear();
    _inFlight.clear();
  }

  /// Deletes cached icons older than [maxAge]. Cheap and bounded: the icon
  /// directory only ever holds small files.
  static Future<void> purgeExpired() async {
    final root = await _root();
    if (root == null) return;
    final now = DateTime.now();
    for (final entity in Directory(root).listSync()) {
      if (entity is! File) continue;
      try {
        if (now.difference(entity.lastModifiedSync()) > maxAge) {
          entity.deleteSync();
        }
      } catch (error) {
        AppLog.d('icons', 'purge skipped an entry (${error.runtimeType})');
      }
    }
  }
}

class _PendingIcon {
  final String scopeKey;
  final File file;
  final Completer<File?> completer;

  _PendingIcon(this.scopeKey, this.file, this.completer);
}

class _PendingAvatar {
  final String scopeKey;
  final File file;
  final Completer<File?> completer;

  _PendingAvatar(this.scopeKey, this.file, this.completer);
}
