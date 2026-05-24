import 'package:kubb_app/features/auth/data/secure_token_store.dart';

/// In-memory drop-in for [SecureTokenStore] so tests can exercise code
/// paths that touch keypair storage without bringing up the
/// flutter_secure_storage MethodChannel.
class FakeSecureTokenStore implements SecureTokenStore {
  final Map<SecureTokenKind, String> _values = <SecureTokenKind, String>{};

  @override
  Future<String?> read(SecureTokenKind kind) async => _values[kind];

  @override
  Future<void> write(SecureTokenKind kind, String value) async {
    _values[kind] = value;
  }

  @override
  Future<void> delete(SecureTokenKind kind) async {
    _values.remove(kind);
  }

  @override
  Future<void> deleteAll() async {
    _values.clear();
  }
}
