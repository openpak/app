/// Where the bearer lives between launches.
///
/// The token is a credential worth thirty days, so it goes in the platform
/// keystore (Keychain on iOS, EncryptedSharedPreferences on Android) rather
/// than plain preferences. Losing it is harmless — the person signs in again —
/// so every read is allowed to fail quietly, but writing it somewhere readable
/// would not be.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Session {
  Session({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const _key = 'openpak.bearer';
  final FlutterSecureStorage _storage;

  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      // A keystore that will not open (a restored backup, a wiped key) means
      // signed out, not crashed.
      return null;
    }
  }

  Future<void> write(String token) => _storage.write(key: _key, value: token);

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}
