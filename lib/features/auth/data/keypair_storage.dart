import 'dart:convert';
import 'dart:typed_data';

import 'package:kubb_app/features/auth/data/crypto_service.dart';
import 'package:kubb_app/features/auth/data/secure_token_store.dart';

/// High-level Ed25519 keypair handling for the auth feature.
///
/// Generates fresh keypairs via [CryptoService], persists the private
/// key in OS-level secure storage via [SecureTokenStore], and serves
/// it back to callers (signing, account upgrade) without the
/// application layer touching either dependency directly.
class KeypairStorage {
  KeypairStorage({
    required CryptoService crypto,
    required SecureTokenStore secureStore,
  })  : _crypto = crypto,
        _secureStore = secureStore;

  final CryptoService _crypto;
  final SecureTokenStore _secureStore;

  /// Generates a new Ed25519 keypair without persisting it.
  Future<Ed25519KeyPairBytes> generate() {
    return _crypto.generateEd25519KeyPair();
  }

  /// Persists [privateKey] (32-byte seed) into OS secure storage.
  Future<void> save(List<int> privateKey) {
    final encoded = base64Encode(privateKey);
    return _secureStore.write(SecureTokenKind.privateKey, encoded);
  }

  /// Returns the persisted 32-byte private-key seed, or null if no
  /// keypair has ever been saved (or after [clear]).
  Future<Uint8List?> load() async {
    final encoded = await _secureStore.read(SecureTokenKind.privateKey);
    if (encoded == null) return null;
    return Uint8List.fromList(base64Decode(encoded));
  }

  /// Removes the persisted private key. Used on sign-out and on
  /// account deletion.
  Future<void> clear() {
    return _secureStore.delete(SecureTokenKind.privateKey);
  }
}
