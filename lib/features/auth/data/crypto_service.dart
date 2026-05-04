import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;

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

  /// Derives a `params.hashLength`-byte key from a passphrase using
  /// Argon2id. Runs in a separate isolate via Flutter's `compute` so
  /// the UI thread stays unblocked during the memory-hard derivation.
  ///
  /// Web has no real isolates — `compute` runs the callback in the
  /// same event loop. The reduced web parameters from
  /// [Argon2idParams.platformDefault] keep this acceptable.
  Future<Uint8List> deriveKeyArgon2id({
    required List<int> passphrase,
    required List<int> salt,
    required Argon2idParams params,
  }) {
    final msg = _Argon2idIsolateMessage(
      passphrase: passphrase,
      salt: salt,
      params: params,
    );
    return compute(_argon2idIsolateEntry, msg);
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

/// Argon2id parameters that travel with each encrypted backup row in
/// the server-side `kdf_params` jsonb column. Keeping them on the row
/// means a backup created with one parameter set can still be
/// decrypted later even if the platform default changes.
class Argon2idParams {
  const Argon2idParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    this.hashLength = 32,
  });

  factory Argon2idParams.fromJson(Map<String, Object?> json) {
    return Argon2idParams(
      memoryKiB: json['m']! as int,
      iterations: json['t']! as int,
      parallelism: json['p']! as int,
      hashLength: (json['l'] as int?) ?? 32,
    );
  }

  /// Per-platform default at backup-creation time. Native uses 64 MiB
  /// with four lanes; web drops to 32 MiB and a single lane (browser
  /// JS is single-threaded — extra lanes add no security margin and
  /// cost memory). See
  /// `docs/plans/auth-oauth-keypair/spike-argon2id.md`.
  factory Argon2idParams.platformDefault() {
    return const Argon2idParams(
      memoryKiB: kIsWeb ? 32768 : 65536,
      iterations: 3,
      parallelism: kIsWeb ? 1 : 4,
    );
  }

  /// Memory parameter in KiB. OWASP recommends 65536 (64 MiB) for
  /// native; the spike (`docs/plans/auth-oauth-keypair/spike-argon2id.md`)
  /// drops this to 32768 (32 MiB) on web.
  final int memoryKiB;

  /// Number of iterations.
  final int iterations;

  /// Lane / parallelism count.
  final int parallelism;

  /// Output key length in bytes (default 32 — XChaCha20 key size).
  final int hashLength;

  Map<String, Object> toJson() => <String, Object>{
        'algo': 'argon2id',
        'm': memoryKiB,
        't': iterations,
        'p': parallelism,
        if (hashLength != 32) 'l': hashLength,
      };
}

/// Top-level isolate entry point for [CryptoService.deriveKeyArgon2id].
/// Flutter's `compute()` requires the callback to be a top-level (or
/// static) function so the isolate can resolve it without capturing
/// closure state.
Future<Uint8List> _argon2idIsolateEntry(_Argon2idIsolateMessage msg) async {
  final algo = Argon2id(
    memory: msg.params.memoryKiB,
    parallelism: msg.params.parallelism,
    iterations: msg.params.iterations,
    hashLength: msg.params.hashLength,
  );
  final secret = SecretKey(msg.passphrase);
  final result = await algo.deriveKey(secretKey: secret, nonce: msg.salt);
  final bytes = await result.extractBytes();
  return Uint8List.fromList(bytes);
}

/// Wire-message for the Argon2id isolate entry. Holds bytes only —
/// no SecretKey or other types whose isolate-portability is doubtful.
class _Argon2idIsolateMessage {
  const _Argon2idIsolateMessage({
    required this.passphrase,
    required this.salt,
    required this.params,
  });

  final List<int> passphrase;
  final List<int> salt;
  final Argon2idParams params;
}
