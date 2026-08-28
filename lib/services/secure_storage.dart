import 'package:flutter/services.dart';

/// Android Keystore-backed storage implemented by [SecureStorage] on the
/// platform side. Values never enter SharedPreferences in plaintext.
class SecureStorage {
  SecureStorage._();

  static const MethodChannel _channel = MethodChannel(
    'com.senlinjun.nek0/secure_storage',
  );

  static const String identityKey = 'client_identity';

  static String serverPasswordKey(String serverId) =>
      'server_password_$serverId';

  static String channelPasswordKey(String serverId) =>
      'channel_password_$serverId';

  static Future<String?> get(String key) async {
    return _channel.invokeMethod<String>('get', {'key': key});
  }

  static Future<void> put(String key, String value) async {
    final saved = await _channel.invokeMethod<bool>('put', {
      'key': key,
      'value': value,
    });
    if (saved != true) {
      throw StateError('Android secure storage did not confirm the write');
    }
  }

  static Future<void> delete(String key) async {
    final deleted = await _channel.invokeMethod<bool>('delete', {'key': key});
    if (deleted != true) {
      throw StateError('Android secure storage did not confirm the delete');
    }
  }
}
