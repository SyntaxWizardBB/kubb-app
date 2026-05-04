import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/data/keypair_backup_repository.dart';

part 'passphrase_change_controller.freezed.dart';

@freezed
class PassphraseChangeState with _$PassphraseChangeState {
  const factory PassphraseChangeState.idle() = _PCIdle;
  const factory PassphraseChangeState.changing() = _PCChanging;
  const factory PassphraseChangeState.done() = _PCDone;
  const factory PassphraseChangeState.failed({required String reason}) =
      _PCFailed;
}

final passphraseChangeControllerProvider =
    NotifierProvider<PassphraseChangeController, PassphraseChangeState>(
        PassphraseChangeController.new);

class PassphraseChangeController extends Notifier<PassphraseChangeState> {
  @override
  PassphraseChangeState build() => const PassphraseChangeState.idle();

  Future<void> change({
    required String nickname,
    required String oldPassphrase,
    required String newPassphrase,
  }) async {
    state = const PassphraseChangeState.changing();
    final telemetry = ref.read(authTelemetryProvider);
    try {
      await ref.read(keypairBackupRepositoryProvider).updatePassphrase(
            nickname: nickname,
            oldPassphrase: oldPassphrase,
            newPassphrase: newPassphrase,
          );
      final userId = ref.read(supabaseAuthAdapterProvider).currentState.userId;
      if (userId != null) {
        telemetry
          ..passphraseChanged(userId: userId)
          ..keypairBackupRotated(userId: userId);
      }
      state = const PassphraseChangeState.done();
    } on KeypairRestoreFailed catch (e) {
      state = PassphraseChangeState.failed(reason: e.message);
    } on Object catch (e) {
      state = PassphraseChangeState.failed(reason: e.toString());
    }
  }
}
