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
  CryptoService({Ed25519? ed25519, Xchacha20? xchacha20})
      : _ed25519 = ed25519 ?? Ed25519(),
        _xchacha20 = xchacha20 ?? Xchacha20.poly1305Aead();

  final Ed25519 _ed25519;
  final Xchacha20 _xchacha20;

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

  /// Encrypts [plaintext] with XChaCha20-Poly1305 AEAD. Returns the
  /// concatenated ciphertext (`bytes || mac`) — the caller stores the
  /// ciphertext alongside the [nonce], both of which are needed for
  /// decryption. Key length is 32 bytes; nonce length is 24 bytes.
  Future<Uint8List> encryptXChaCha20({
    required List<int> key,
    required List<int> plaintext,
    required List<int> nonce,
  }) async {
    final box = await _xchacha20.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    final out = Uint8List(box.cipherText.length + box.mac.bytes.length)
      ..setRange(0, box.cipherText.length, box.cipherText)
      ..setRange(box.cipherText.length, box.cipherText.length + box.mac.bytes.length,
          box.mac.bytes);
    return out;
  }

  /// Decrypts a [ciphertext] produced by [encryptXChaCha20]. Throws a
  /// [SecretBoxAuthenticationError] if the MAC does not verify (which
  /// happens when key, nonce or ciphertext have been tampered with).
  Future<Uint8List> decryptXChaCha20({
    required List<int> key,
    required List<int> ciphertext,
    required List<int> nonce,
  }) async {
    const macLength = 16;
    if (ciphertext.length < macLength) {
      throw ArgumentError(
        'ciphertext must be at least $macLength bytes (got ${ciphertext.length})',
      );
    }
    final body = ciphertext.sublist(0, ciphertext.length - macLength);
    final mac = ciphertext.sublist(ciphertext.length - macLength);
    final box = SecretBox(body, nonce: nonce, mac: Mac(mac));
    final plain = await _xchacha20.decrypt(box, secretKey: SecretKey(key));
    return Uint8List.fromList(plain);
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
