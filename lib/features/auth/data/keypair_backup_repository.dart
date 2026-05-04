import 'dart:typed_data';

/// Result of a successful backup restore.
class KeypairRestoreResult {
  const KeypairRestoreResult({
    required this.privateKey,
    required this.publicKey,
  });

  final Uint8List privateKey;
  final Uint8List publicKey;
}

/// Encrypted backup material ready to be persisted on the server. Used
/// during account setup so the ciphertext, salt and KDF parameters can
/// be passed to the `keypair_attach` RPC in the same transaction that
/// inserts the credential row — avoiding a window in which a partial
/// row exists with placeholder ciphertext.
class KeypairBackupMaterial {
  const KeypairBackupMaterial({
    required this.ciphertext,
    required this.kdfSalt,
    required this.kdfParams,
  });

  final Uint8List ciphertext;
  final Uint8List kdfSalt;
  final Map<String, Object> kdfParams;
}

/// Thrown when the passphrase does not decrypt the stored backup, or
/// when no backup exists for the requested nickname. Both surface as
/// the same error so the client cannot infer whether the nickname is
/// taken (per ADR-0010 §AK-4 enumeration-resistance).
class KeypairRestoreFailed implements Exception {
  const KeypairRestoreFailed([this.message = 'restore failed']);
  final String message;

  @override
  String toString() => 'KeypairRestoreFailed: $message';
}

/// Manages the encrypted-server-backup half of the anonymous keypair
/// flow. Argon2id derives the encryption key from the user-chosen
/// passphrase; XChaCha20-Poly1305 encrypts the 32-byte private-key
/// seed; the ciphertext travels with the per-row `kdf_params` so the
/// algorithm parameters can change in the future without breaking
/// existing backups (per ADR-0010 §AK-3).
abstract class KeypairBackupRepository {
  /// Encrypts [privateKey] with the [passphrase] and returns the
  /// resulting backup material without touching the network. Account
  /// setup uses this so the ciphertext can travel with the
  /// `keypair_attach` RPC in a single transaction (per ADR-0010 §AK-1)
  /// — calling [uploadBackup] after a successful attach would leave a
  /// partial row behind on failure.
  Future<KeypairBackupMaterial> prepareBackup({
    required Uint8List privateKey,
    required Uint8List publicKey,
    required String passphrase,
  });

  /// Encrypts [privateKey] with the [passphrase] and uploads the
  /// resulting backup row keyed by `sha256(nickname || server_salt)`.
  /// Returns silently on success. Used by passphrase rotation and
  /// other flows that already have an active session and a row to
  /// upsert into; account setup uses [prepareBackup] instead so the
  /// initial insert lands in the same transaction as the credential
  /// row.
  Future<void> uploadBackup({
    required String nickname,
    required Uint8List privateKey,
    required Uint8List publicKey,
    required String passphrase,
  });

  /// Looks up the backup row for [nickname], decrypts with [passphrase],
  /// and returns the recovered private key. Throws [KeypairRestoreFailed]
  /// when the row is missing OR the passphrase does not decrypt.
  Future<KeypairRestoreResult> restoreBackup({
    required String nickname,
    required String passphrase,
  });

  /// Re-encrypts the existing backup with [newPassphrase]. Requires
  /// the current [oldPassphrase] to verify the user controls the
  /// existing row.
  Future<void> updatePassphrase({
    required String nickname,
    required String oldPassphrase,
    required String newPassphrase,
  });

  /// Removes the backup row for the current user. Used by
  /// account-deletion.
  Future<void> deleteBackup({required String nickname});

  /// Returns the `updated_at` of the backup row owned by [userId], or
  /// `null` when no row exists. Used by the settings screen to surface
  /// a "backup recommended" warning when the row is missing or stale
  /// (per design-brief #14).
  Future<DateTime?> backupTimestamp({required String userId});
}
