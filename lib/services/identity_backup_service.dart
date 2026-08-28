import 'package:flutter/services.dart';

import 'app_log.dart';

const _tag = 'identity_backup';

/// Portable, password-protected backup/restore of the TeamSpeak identity.
///
/// The actual cryptography (PBKDF2-HMAC-SHA256 + AES-GCM) runs on the Android
/// side in [IdentityBackup], so no secret ever passes through Dart in the
/// clear except the one-shot password the user typed. Export returns a single
/// portable string; import accepts the same string back.
class IdentityBackupService {
  IdentityBackupService._();

  static const _channel = MethodChannel('com.senlinjun.nek0/identity_backup');

  /// Seals [identity] under [password]. Returns a portable, self-contained
  /// blob. Throws a [PlatformException] with code `bad_password`/`error` on
  /// failure.
  static Future<String> export(String identity, String password) async {
    if (password.trim().isEmpty) {
      throw const FormatException('Password must not be empty');
    }
    final blob = await _channel.invokeMethod<String>('encrypt', {
      'value': identity,
      'password': password,
    });
    if (blob == null || blob.isEmpty) {
      throw StateError('Android did not return a backup blob');
    }
    AppLog.i(_tag, 'identity exported (${blob.length} chars, sealed)');
    return blob;
  }

  /// Unseals [blob] with [password]. Throws a [PlatformException] with code
  /// `bad_password` when the password is wrong, `bad_format` for a malformed
  /// blob.
  static Future<String> import(String blob, String password) async {
    final identity = await _channel.invokeMethod<String>('decrypt', {
      'blob': blob.trim(),
      'password': password,
    });
    if (identity == null) {
      throw StateError('Android did not return a decrypted identity');
    }
    AppLog.i(_tag, 'identity imported (${identity.length} chars)');
    return identity;
  }

  /// True when [blob] looks like a backup this app produced (a cheap,
  /// non-cryptographic sanity check before prompting for a password).
  static bool looksLikeBlob(String blob) =>
      blob.trim().startsWith('nekobackup1:');
}
