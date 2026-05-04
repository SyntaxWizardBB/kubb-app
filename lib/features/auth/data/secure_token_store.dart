import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Distinct kinds of credential material that the auth feature stores
/// in OS-level secure storage.
enum SecureTokenKind {
  accessToken('auth_access_token'),
  refreshToken('auth_refresh_token'),
  oauthToken('auth_oauth_token'),
  privateKey('auth_private_key');

  const SecureTokenKind(this.storageKey);

  /// The key under which the value is stored in [FlutterSecureStorage].
  final String storageKey;
}

/// Wraps [FlutterSecureStorage] for the four credential kinds the auth
/// feature needs. Single point of truth for storage-key naming, so
/// audits stay simple and so the test suite can swap in a fake.
class SecureTokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<String?> read(SecureTokenKind kind) {
    return _storage.read(key: kind.storageKey);
  }

  Future<void> write(SecureTokenKind kind, String value) {
    return _storage.write(key: kind.storageKey, value: value);
  }

  Future<void> delete(SecureTokenKind kind) {
    return _storage.delete(key: kind.storageKey);
  }

  Future<void> deleteAll() async {
    for (final kind in SecureTokenKind.values) {
      await _storage.delete(key: kind.storageKey);
    }
  }
}
