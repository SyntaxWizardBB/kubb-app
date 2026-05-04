import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Façade over the `cryptography` package's Ed25519, Argon2id and
/// XChaCha20-Poly1305 primitives.
///
/// Each public method works with raw byte lists so the auth feature can
/// move keys, signatures and ciphertexts around without leaking
/// `cryptography`'s wrapper types into the application layer.
///
/// Concrete algorithm classes are constructor-injected so tests can
/// substitute deterministic / faster implementations when they need to.
class CryptoService {
  CryptoService({Ed25519? ed25519}) : _ed25519 = ed25519 ?? Ed25519();

  final Ed25519 _ed25519;

  /// Generates a fresh Ed25519 keypair. Public key is 32 bytes, private
  /// key is 32 bytes (the seed; the cryptography package derives the
  /// 64-byte expanded private key on demand).
  Future<Ed25519KeyPairBytes> generateEd25519KeyPair() async {
    final pair = await _ed25519.newKeyPair();
    final publicKey = await pair.extractPublicKey();
    final privateKey = await pair.extractPrivateKeyBytes();
    return Ed25519KeyPairBytes(
      publicKey: Uint8List.fromList(publicKey.bytes),
      privateKey: Uint8List.fromList(privateKey),
    );
  }

  /// Signs [message] with [privateKey] (32-byte seed). Returns the
  /// 64-byte signature.
  Future<Uint8List> signEd25519({
    required List<int> privateKey,
    required List<int> message,
  }) async {
    final keyPair = await _ed25519.newKeyPairFromSeed(privateKey);
    final signature = await _ed25519.sign(message, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  /// Verifies a signature against a public key. Returns true iff the
  /// signature is valid.
  Future<bool> verifyEd25519({
    required List<int> publicKey,
    required List<int> message,
    required List<int> signature,
  }) async {
    return _ed25519.verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
  }
}

/// Plain value object for an Ed25519 keypair as raw bytes. Lives outside
/// the `cryptography` package's wrapper types so callers do not need to
/// import the third-party SimpleKeyPair API.
class Ed25519KeyPairBytes {
  const Ed25519KeyPairBytes({
    required this.publicKey,
    required this.privateKey,
  });

  /// 32-byte Ed25519 public key.
  final Uint8List publicKey;

  /// 32-byte Ed25519 private-key seed.
  final Uint8List privateKey;
}
