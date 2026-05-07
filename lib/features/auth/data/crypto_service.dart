import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';

/// Façade over the `cryptography` package's Ed25519 and
/// XChaCha20-Poly1305 primitives, plus BIP-39 mnemonic generation /
/// validation / seed derivation per ADR-0011.
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

  /// Re-derives the public key from a 32-byte Ed25519 seed. Used by
  /// the restore-sign-in path: the device only persists the seed in
  /// secure storage, but the server-side challenge lookup is keyed by
  /// the public key.
  Future<Uint8List> publicKeyFromSeed(List<int> seed) async {
    final keyPair = await _ed25519.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    return Uint8List.fromList(publicKey.bytes);
  }

  /// Generates a fresh BIP-39 mnemonic of the given length. Per
  /// ADR-0011 the UI exposes 12, 15, and 18; the helper accepts any
  /// valid BIP-39 length so power-user toggles can lift the cap later
  /// without changes here. Strength bits per length: 128/160/192/224/256.
  String generateBip39Mnemonic({int wordCount = 12}) {
    return bip39.generateMnemonic(strength: _strengthForWordCount(wordCount));
  }

  /// Validates that [mnemonic] parses as a BIP-39 phrase and that its
  /// embedded checksum is correct. Used both at restore-time (catch
  /// typos) and at confirm-mnemonic time during signup.
  bool isValidBip39Mnemonic(String mnemonic) {
    return bip39.validateMnemonic(_normalizeMnemonic(mnemonic));
  }

  /// Derives the Ed25519 keypair from a BIP-39 mnemonic. The phrase is
  /// stretched to a 64-byte BIP-39 seed (PBKDF2-HMAC-SHA512, 2048
  /// rounds, salt = "mnemonic"), the first 32 bytes of which become
  /// the Ed25519 secret seed. We do not use SLIP-0010 derivation —
  /// there is no HD path, only a single root keypair per account.
  ///
  /// Throws [FormatException] if the mnemonic does not validate.
  Future<Ed25519KeyPairBytes> keypairFromMnemonic(String mnemonic) async {
    final normalized = _normalizeMnemonic(mnemonic);
    if (!bip39.validateMnemonic(normalized)) {
      throw const FormatException('mnemonic checksum failed');
    }
    final seed = bip39.mnemonicToSeed(normalized);
    final ed25519Seed = Uint8List.fromList(seed.sublist(0, 32));
    final keyPair = await _ed25519.newKeyPairFromSeed(ed25519Seed);
    final publicKey = await keyPair.extractPublicKey();
    return Ed25519KeyPairBytes(
      publicKey: Uint8List.fromList(publicKey.bytes),
      privateKey: ed25519Seed,
    );
  }

  static int _strengthForWordCount(int words) {
    switch (words) {
      case 12:
        return 128;
      case 15:
        return 160;
      case 18:
        return 192;
      case 21:
        return 224;
      case 24:
        return 256;
      default:
        throw ArgumentError(
          'BIP-39 word count must be 12, 15, 18, 21, or 24 (got $words)',
        );
    }
  }

  static String _normalizeMnemonic(String input) {
    // BIP-39 wordlist words are lowercase ASCII. Collapse whitespace
    // (including tabs / newlines from paste-friendly input) and
    // lowercase so user input matches the dictionary entries.
    return input.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
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
