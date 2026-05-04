import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:kubb_app/features/auth/data/crypto_service.dart';
import 'package:kubb_app/features/auth/data/keypair_backup_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Production [KeypairBackupRepository] backed by Supabase Postgres.
///
/// The nickname hash is computed server-side via the
/// `auth.compute_nickname_hash(nickname)` RPC so the salt never leaves
/// the database. Argon2id derives the encryption key from the
/// passphrase locally; the server only ever sees the ciphertext.
class KeypairBackupRepositoryImpl implements KeypairBackupRepository {
  KeypairBackupRepositoryImpl({
    required SupabaseClient client,
    required CryptoService crypto,
    Random? random,
  })  : _client = client,
        _crypto = crypto,
        _random = random ?? Random.secure();

  final SupabaseClient _client;
  final CryptoService _crypto;
  final Random _random;

  Future<String> _hashNickname(String nickname) async {
    final response = await _client.rpc<String>(
      'compute_nickname_hash',
      params: <String, dynamic>{'p_nickname': nickname},
    );
    return response;
  }

  Uint8List _randomBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  @override
  Future<KeypairBackupMaterial> prepareBackup({
    required Uint8List privateKey,
    required Uint8List publicKey,
    required String passphrase,
  }) async {
    final params = Argon2idParams.platformDefault();
    final salt = _randomBytes(16);
    final nonce = _randomBytes(24);

    final key = await _crypto.deriveKeyArgon2id(
      passphrase: passphrase.codeUnits,
      salt: salt,
      params: params,
    );

    final ciphertext = await _crypto.encryptXChaCha20(
      key: key,
      plaintext: _frameKeypair(privateKey, publicKey, nonce),
      nonce: nonce,
    );

    return KeypairBackupMaterial(
      ciphertext: ciphertext,
      kdfSalt: salt,
      kdfParams: params.toJson(),
    );
  }

  @override
  Future<void> uploadBackup({
    required String nickname,
    required Uint8List privateKey,
    required Uint8List publicKey,
    required String passphrase,
  }) async {
    final material = await prepareBackup(
      privateKey: privateKey,
      publicKey: publicKey,
      passphrase: passphrase,
    );

    final nicknameHash = await _hashNickname(nickname);
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('uploadBackup requires an active session');
    }

    await _client.from('user_keypair_backups').upsert(<String, dynamic>{
      'user_id': userId,
      'nickname_hash': nicknameHash,
      'ciphertext': base64Encode(material.ciphertext),
      'kdf_salt': base64Encode(material.kdfSalt),
      'kdf_params': material.kdfParams,
    });
  }

  @override
  Future<KeypairRestoreResult> restoreBackup({
    required String nickname,
    required String passphrase,
  }) async {
    final nicknameHash = await _hashNickname(nickname);

    final rows = await _client
        .from('user_keypair_backups')
        .select('ciphertext, kdf_salt, kdf_params')
        .eq('nickname_hash', nicknameHash)
        .limit(1);

    if (rows.isEmpty) {
      throw const KeypairRestoreFailed('no backup for nickname');
    }
    final row = rows.first;
    final ciphertext = base64Decode(row['ciphertext'] as String);
    final salt = base64Decode(row['kdf_salt'] as String);
    final params = Argon2idParams.fromJson(
      (row['kdf_params'] as Map).cast<String, Object?>(),
    );

    final key = await _crypto.deriveKeyArgon2id(
      passphrase: passphrase.codeUnits,
      salt: salt,
      params: params,
    );

    // The nonce is the first 24 bytes of the framed plaintext we
    // wrote in uploadBackup. We pass the same nonce to the AEAD
    // because the framing keeps it bound to the ciphertext.
    final nonce = ciphertext.sublist(0, 24);
    final body = ciphertext.sublist(24);

    try {
      final plain = await _crypto.decryptXChaCha20(
        key: key,
        ciphertext: body,
        nonce: nonce,
      );
      return _unframeKeypair(plain);
    } on SecretBoxAuthenticationError {
      throw const KeypairRestoreFailed('passphrase mismatch');
    }
  }

  @override
  Future<void> updatePassphrase({
    required String nickname,
    required String oldPassphrase,
    required String newPassphrase,
  }) async {
    final restored = await restoreBackup(
      nickname: nickname,
      passphrase: oldPassphrase,
    );
    await uploadBackup(
      nickname: nickname,
      privateKey: restored.privateKey,
      publicKey: restored.publicKey,
      passphrase: newPassphrase,
    );
  }

  @override
  Future<void> deleteBackup({required String nickname}) async {
    final nicknameHash = await _hashNickname(nickname);
    await _client
        .from('user_keypair_backups')
        .delete()
        .eq('nickname_hash', nicknameHash);
  }

  @override
  Future<DateTime?> backupTimestamp({required String userId}) async {
    final rows = await _client
        .from('user_keypair_backups')
        .select('updated_at')
        .eq('user_id', userId)
        .limit(1);
    if (rows.isEmpty) {
      return null;
    }
    final raw = rows.first['updated_at'];
    if (raw is String) {
      return DateTime.parse(raw);
    }
    if (raw is DateTime) {
      return raw;
    }
    return null;
  }

  /// Frames the (privateKey, publicKey, nonce) tuple as a single byte
  /// blob: nonce(24) || privateKey(32) || publicKey(32). Encryption
  /// covers the framed blob so the AEAD MAC also authenticates the
  /// public key, which protects against a server that swaps in a
  /// stranger's public key.
  Uint8List _frameKeypair(
    Uint8List privateKey,
    Uint8List publicKey,
    Uint8List nonce,
  ) {
    final out = Uint8List(nonce.length + privateKey.length + publicKey.length)
      ..setRange(0, nonce.length, nonce)
      ..setRange(nonce.length, nonce.length + privateKey.length, privateKey)
      ..setRange(
          nonce.length + privateKey.length,
          nonce.length + privateKey.length + publicKey.length,
          publicKey);
    return out;
  }

  KeypairRestoreResult _unframeKeypair(Uint8List plain) {
    if (plain.length < 24 + 32 + 32) {
      throw const KeypairRestoreFailed('decrypted payload truncated');
    }
    final privateKey = plain.sublist(24, 24 + 32);
    final publicKey = plain.sublist(24 + 32, 24 + 32 + 32);
    return KeypairRestoreResult(
      privateKey: Uint8List.fromList(privateKey),
      publicKey: Uint8List.fromList(publicKey),
    );
  }
}
