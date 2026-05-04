import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:kubb_app/features/auth/data/crypto_service.dart';
import 'package:kubb_app/features/auth/data/keypair_backup_repository.dart';

/// Test double for [KeypairBackupRepository] that runs real Argon2id +
/// XChaCha20 (so encrypt/decrypt symmetry is genuinely verified) but
/// keeps the "server" rows in an in-memory map keyed by nickname.
///
/// Tiny Argon2id parameters keep the test suite fast.
class FakeKeypairBackupRepository implements KeypairBackupRepository {
  FakeKeypairBackupRepository({CryptoService? crypto})
      : _crypto = crypto ?? CryptoService();

  final CryptoService _crypto;
  final Map<String, _BackupRow> _rows = <String, _BackupRow>{};

  /// Per-userId override the AccountSection-test uses to simulate a
  /// missing or stale backup. Keys are user ids, values the
  /// `updated_at` the repository should return.
  final Map<String, DateTime> timestampsByUserId = <String, DateTime>{};

  static const Argon2idParams _testParams = Argon2idParams(
    memoryKiB: 8,
    iterations: 1,
    parallelism: 1,
  );

  Iterable<String> get storedNicknames => _rows.keys;

  /// Last [prepareBackup] result the controller pulled out of the
  /// repository, exposed so tests can assert it travelled into
  /// the FakeSupabaseAuthAdapter's attachKeypair call verbatim.
  KeypairBackupMaterial? lastPreparedMaterial;

  @override
  Future<KeypairBackupMaterial> prepareBackup({
    required Uint8List privateKey,
    required Uint8List publicKey,
    required String passphrase,
  }) async {
    final salt = Uint8List.fromList(List.generate(16, (i) => i));
    final key = await _crypto.deriveKeyArgon2id(
      passphrase: passphrase.codeUnits,
      salt: salt,
      params: _testParams,
    );
    final nonce = Uint8List.fromList(List.generate(24, (i) => i + 100));
    final ciphertext = await _crypto.encryptXChaCha20(
      key: key,
      plaintext: privateKey,
      nonce: nonce,
    );
    final material = KeypairBackupMaterial(
      ciphertext: ciphertext,
      kdfSalt: salt,
      kdfParams: _testParams.toJson(),
    );
    lastPreparedMaterial = material;
    return material;
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
    _rows[nickname] = _BackupRow(
      ciphertext: material.ciphertext,
      salt: material.kdfSalt,
      nonce: Uint8List.fromList(List.generate(24, (i) => i + 100)),
      params: _testParams,
      publicKey: publicKey,
    );
  }

  @override
  Future<KeypairRestoreResult> restoreBackup({
    required String nickname,
    required String passphrase,
  }) async {
    final row = _rows[nickname];
    if (row == null) {
      throw const KeypairRestoreFailed('no backup for nickname');
    }
    final key = await _crypto.deriveKeyArgon2id(
      passphrase: passphrase.codeUnits,
      salt: row.salt,
      params: row.params,
    );
    try {
      final plain = await _crypto.decryptXChaCha20(
        key: key,
        ciphertext: row.ciphertext,
        nonce: row.nonce,
      );
      return KeypairRestoreResult(
        privateKey: plain,
        publicKey: row.publicKey,
      );
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
    _rows.remove(nickname);
  }

  @override
  Future<DateTime?> backupTimestamp({required String userId}) async {
    return timestampsByUserId[userId];
  }
}

class _BackupRow {
  const _BackupRow({
    required this.ciphertext,
    required this.salt,
    required this.nonce,
    required this.params,
    required this.publicKey,
  });

  final Uint8List ciphertext;
  final Uint8List salt;
  final Uint8List nonce;
  final Argon2idParams params;
  final Uint8List publicKey;
}
