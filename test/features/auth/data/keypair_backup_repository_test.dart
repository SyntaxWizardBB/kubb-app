import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/data/crypto_service.dart';
import 'package:kubb_app/features/auth/data/keypair_backup_repository.dart';

import '../../../fixtures/auth/fake_keypair_backup_repository.dart';

/// Contract tests for [KeypairBackupRepository] driven through
/// [FakeKeypairBackupRepository]. The fake runs real Argon2id and
/// XChaCha20 internally so the encrypt/decrypt symmetry is genuinely
/// exercised; only the "server" side is stubbed.
void main() {
  late FakeKeypairBackupRepository repo;
  late CryptoService crypto;
  late Ed25519KeyPairBytes pair;

  setUp(() async {
    crypto = CryptoService();
    repo = FakeKeypairBackupRepository(crypto: crypto);
    pair = await crypto.generateEd25519KeyPair();
  });

  test('upload then restore round-trips the private key', () async {
    await repo.uploadBackup(
      nickname: 'lukas',
      privateKey: pair.privateKey,
      publicKey: pair.publicKey,
      passphrase: 'correct-horse-battery-staple',
    );

    final restored = await repo.restoreBackup(
      nickname: 'lukas',
      passphrase: 'correct-horse-battery-staple',
    );

    expect(restored.privateKey, equals(pair.privateKey));
    expect(restored.publicKey, equals(pair.publicKey));
  });

  test('restore with wrong passphrase throws KeypairRestoreFailed',
      () async {
    await repo.uploadBackup(
      nickname: 'lukas',
      privateKey: pair.privateKey,
      publicKey: pair.publicKey,
      passphrase: 'correct',
    );

    await expectLater(
      repo.restoreBackup(nickname: 'lukas', passphrase: 'wrong'),
      throwsA(isA<KeypairRestoreFailed>()),
    );
  });

  test('restore with unknown nickname throws KeypairRestoreFailed', () async {
    await expectLater(
      repo.restoreBackup(nickname: 'never-saved', passphrase: 'whatever'),
      throwsA(isA<KeypairRestoreFailed>()),
    );
  });

  test('updatePassphrase rotates the encryption key', () async {
    await repo.uploadBackup(
      nickname: 'lukas',
      privateKey: pair.privateKey,
      publicKey: pair.publicKey,
      passphrase: 'old-passphrase',
    );

    await repo.updatePassphrase(
      nickname: 'lukas',
      oldPassphrase: 'old-passphrase',
      newPassphrase: 'new-passphrase',
    );

    // Old passphrase no longer decrypts.
    await expectLater(
      repo.restoreBackup(
        nickname: 'lukas',
        passphrase: 'old-passphrase',
      ),
      throwsA(isA<KeypairRestoreFailed>()),
    );

    // New passphrase does.
    final restored = await repo.restoreBackup(
      nickname: 'lukas',
      passphrase: 'new-passphrase',
    );
    expect(restored.privateKey, equals(pair.privateKey));
  });

  test('updatePassphrase fails when oldPassphrase is wrong', () async {
    await repo.uploadBackup(
      nickname: 'lukas',
      privateKey: pair.privateKey,
      publicKey: pair.publicKey,
      passphrase: 'real-old',
    );

    await expectLater(
      repo.updatePassphrase(
        nickname: 'lukas',
        oldPassphrase: 'wrong-old',
        newPassphrase: 'new-passphrase',
      ),
      throwsA(isA<KeypairRestoreFailed>()),
    );
  });

  test('deleteBackup removes the row so restore then fails', () async {
    await repo.uploadBackup(
      nickname: 'lukas',
      privateKey: pair.privateKey,
      publicKey: pair.publicKey,
      passphrase: 'pp',
    );
    expect(repo.storedNicknames, contains('lukas'));

    await repo.deleteBackup(nickname: 'lukas');
    expect(repo.storedNicknames, isNot(contains('lukas')));

    await expectLater(
      repo.restoreBackup(nickname: 'lukas', passphrase: 'pp'),
      throwsA(isA<KeypairRestoreFailed>()),
    );
  });

  test('two distinct accounts coexist independently', () async {
    final pair2 = await crypto.generateEd25519KeyPair();

    await repo.uploadBackup(
      nickname: 'lukas',
      privateKey: pair.privateKey,
      publicKey: pair.publicKey,
      passphrase: 'pw-1',
    );
    await repo.uploadBackup(
      nickname: 'other',
      privateKey: pair2.privateKey,
      publicKey: pair2.publicKey,
      passphrase: 'pw-2',
    );

    final restored1 = await repo.restoreBackup(
      nickname: 'lukas',
      passphrase: 'pw-1',
    );
    final restored2 = await repo.restoreBackup(
      nickname: 'other',
      passphrase: 'pw-2',
    );

    expect(restored1.privateKey, equals(pair.privateKey));
    expect(restored2.privateKey, equals(pair2.privateKey));
    expect(restored1.privateKey, isNot(equals(restored2.privateKey)));
  });
}
