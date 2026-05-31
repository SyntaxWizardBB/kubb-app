import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/data/crypto_service.dart';
import 'package:kubb_app/features/auth/data/keypair_storage.dart';
import 'package:kubb_app/features/auth/data/secure_token_store.dart';

part 'account_setup_controller.freezed.dart';

/// Multi-step state for the anonymous-account-setup wizard.
///
/// Per ADR-0011 the wizard generates a BIP-39 mnemonic locally, the
/// user writes it down, the user re-enters a few words to confirm, and
/// only then is the keypair derived and attached to the server.
@freezed
class AccountSetupState with _$AccountSetupState {
  const factory AccountSetupState.idle() = _Idle;
  const factory AccountSetupState.nicknameEntered({required String nickname}) =
      _NicknameEntered;

  /// Mnemonic has been generated locally and is shown to the user. The
  /// keypair is *not* attached yet — that happens after confirmation.
  const factory AccountSetupState.mnemonicReady({
    required String nickname,
    required String mnemonic,
    required int wordCount,
  }) = _MnemonicReady;

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

final accountSetupControllerProvider =
    NotifierProvider<AccountSetupController, AccountSetupState>(
        AccountSetupController.new);

class AccountSetupController extends Notifier<AccountSetupState> {
  @override
  AccountSetupState build() => const AccountSetupState.idle();

  void setNickname(String nickname) {
    state = AccountSetupState.nicknameEntered(nickname: nickname);
  }

  /// Generates a BIP-39 mnemonic of [wordCount] words and transitions
  /// the wizard into the "show mnemonic" phase. Does not touch the
  /// network — the keypair is only registered with the server in
  /// [submitConfirmed], after the user has acknowledged the phrase.
  void generateMnemonic({required String nickname, int wordCount = 12}) {
    final crypto = ref.read(cryptoServiceProvider);
    final mnemonic = crypto.generateBip39Mnemonic(wordCount: wordCount);
    state = AccountSetupState.mnemonicReady(
      nickname: nickname,
      mnemonic: mnemonic,
      wordCount: wordCount,
    );
  }

  /// Drives the actual server-side setup, called once the user has
  /// confirmed they wrote the mnemonic down:
  ///   1. Anonymous Supabase session via the adapter.
  ///   2. Derive Ed25519 keypair from the mnemonic (BIP-39 → seed →
  ///      first 32 bytes as Ed25519 secret seed).
  ///   3. keypair_register RPC: server inserts user_credentials and
  ///      user_profiles in a single transaction.
  ///   4. KeypairStorage.save persists the private-key seed in OS
  ///      secure-storage. Last so a server-side rejection of the
  ///      register RPC does not leave a key on disk that has no
  ///      matching server row.
  Future<void> submitConfirmed({
    required String nickname,
    required String mnemonic,
    required String earlyAccessCode,
    String? avatarColor,
  }) async {
    state = const AccountSetupState.submitting();
    final adapter = ref.read(supabaseAuthAdapterProvider);
    final keypairStorage = ref.read(keypairStorageProvider);
    final crypto = ref.read(cryptoServiceProvider);
    final telemetry = ref.read(authTelemetryProvider);

    try {
      telemetry.signinAttempt(kind: 'keypair');
      await adapter.signInAnonymously();

      final keypair = await crypto.keypairFromMnemonic(mnemonic);
      await adapter.attachKeypair(
        nickname: nickname,
        publicKey: keypair.publicKey,
        earlyAccessCode: earlyAccessCode,
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
      telemetry.signinSuccess(userId: userId, kind: 'keypair');
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
