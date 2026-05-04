import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/data/crypto_service.dart';
import 'package:kubb_app/features/auth/data/keypair_backup_repository.dart';
import 'package:kubb_app/features/auth/data/keypair_storage.dart';
import 'package:kubb_app/features/auth/data/secure_token_store.dart';

part 'account_setup_controller.freezed.dart';

/// Multi-step state for the anonymous-account-setup wizard.
@freezed
class AccountSetupState with _$AccountSetupState {
  const factory AccountSetupState.idle() = _Idle;
  const factory AccountSetupState.nicknameEntered({required String nickname}) =
      _NicknameEntered;
  const factory AccountSetupState.submitting() = _Submitting;
  const factory AccountSetupState.done({required String userId}) = _Done;
  const factory AccountSetupState.failed({required String reason}) = _Failed;
}

/// Riverpod providers for the dependencies the controller composes.
/// Tests override these with fakes.

final cryptoServiceProvider = Provider<CryptoService>((ref) {
  return CryptoService();
});

final secureTokenStoreProvider = Provider<SecureTokenStore>((ref) {
  return SecureTokenStore();
});

final keypairStorageProvider = Provider<KeypairStorage>((ref) {
  return KeypairStorage(
    crypto: ref.read(cryptoServiceProvider),
    secureStore: ref.read(secureTokenStoreProvider),
  );
});

final keypairBackupRepositoryProvider =
    Provider<KeypairBackupRepository>((ref) {
  throw UnimplementedError(
    'keypairBackupRepositoryProvider must be overridden during '
    'app bootstrap with the real implementation.',
  );
});

final accountSetupControllerProvider =
    NotifierProvider<AccountSetupController, AccountSetupState>(
        AccountSetupController.new);

class AccountSetupController extends Notifier<AccountSetupState> {
  @override
  AccountSetupState build() => const AccountSetupState.idle();

  void setNickname(String nickname) {
    state = AccountSetupState.nicknameEntered(nickname: nickname);
  }

  /// Drives the full setup flow:
  ///   1. Anonymous Supabase session via the adapter.
  ///   2. Generate Ed25519 keypair locally.
  ///   3. Encrypt the private-key seed locally (Argon2id + XChaCha20)
  ///      via [KeypairBackupRepository.prepareBackup] — no server call
  ///      yet.
  ///   4. attachKeypair RPC carrying the real ciphertext / kdf
  ///      parameters: the server inserts user_credentials,
  ///      user_keypair_backups and user_profiles in a single
  ///      transaction. A failure leaves no partial backup row behind.
  ///   5. KeypairStorage.save persists the private key in the OS
  ///      secure-storage. Last so a server-side rejection of the
  ///      attach RPC does not leave a key on disk that has no matching
  ///      server row.
  Future<void> submit({
    required String nickname,
    required String passphrase,
    String? avatarColor,
  }) async {
    state = const AccountSetupState.submitting();
    final adapter = ref.read(supabaseAuthAdapterProvider);
    final keypairStorage = ref.read(keypairStorageProvider);
    final backupRepo = ref.read(keypairBackupRepositoryProvider);
    final telemetry = ref.read(authTelemetryProvider);

    try {
      telemetry.signinAttempt(kind: 'keypair');
      await adapter.signInAnonymously();

      final keypair = await keypairStorage.generate();
      final material = await backupRepo.prepareBackup(
        privateKey: Uint8List.fromList(keypair.privateKey),
        publicKey: Uint8List.fromList(keypair.publicKey),
        passphrase: passphrase,
      );
      await adapter.attachKeypair(
        nickname: nickname,
        publicKey: keypair.publicKey,
        ciphertext: material.ciphertext,
        kdfSalt: material.kdfSalt,
        kdfParams: material.kdfParams,
        avatarColor: avatarColor,
      );
      await keypairStorage.save(keypair.privateKey);

      final userId = adapter.currentState.userId;
      if (userId == null) {
        state = const AccountSetupState.failed(
          reason: 'session_lost_after_attach',
        );
        return;
      }
      telemetry
        ..keypairBackupCreated(userId: userId)
        ..signinSuccess(userId: userId, kind: 'keypair');
      state = AccountSetupState.done(userId: userId);
    } on Object catch (error) {
      telemetry.signinFailure(
        kind: 'keypair',
        reasonCode: error.runtimeType.toString(),
      );
      state = AccountSetupState.failed(reason: error.toString());
    }
  }
}
