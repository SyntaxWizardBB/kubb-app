import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/data/keypair_backup_repository.dart';

part 'account_deletion_controller.freezed.dart';

@freezed
class AccountDeletionState with _$AccountDeletionState {
  const factory AccountDeletionState.idle() = _ADIdle;
  const factory AccountDeletionState.deleting() = _ADDeleting;
  const factory AccountDeletionState.done() = _ADDone;
  const factory AccountDeletionState.failed({required String reason}) =
      _ADFailed;
}

final accountDeletionControllerProvider =
    NotifierProvider<AccountDeletionController, AccountDeletionState>(
        AccountDeletionController.new);

class AccountDeletionController extends Notifier<AccountDeletionState> {
  @override
  AccountDeletionState build() => const AccountDeletionState.idle();

  /// Two-step destructive flow per AK-13. The UI is responsible for
  /// the two confirmation dialogs; this method assumes the user has
  /// already confirmed twice.
  Future<void> delete({String? nickname}) async {
    state = const AccountDeletionState.deleting();
    final adapter = ref.read(supabaseAuthAdapterProvider);
    final keypair = ref.read(keypairStorageProvider);
    final telemetry = ref.read(authTelemetryProvider);
    final userId = adapter.currentState.userId;

    try {
      if (nickname != null) {
        // Best-effort cleanup of the backup row before the cascade
        // takes the rest. If the row is already gone, ignore.
        try {
          await ref
              .read(keypairBackupRepositoryProvider)
              .deleteBackup(nickname: nickname);
        } on KeypairRestoreFailed {
          // Already missing — fine.
        }
      }
      await adapter.deleteCurrentAccount();
      await keypair.clear();
      if (userId != null) telemetry.accountDelete(userId: userId);
      state = const AccountDeletionState.done();
    } on Object catch (e) {
      state = AccountDeletionState.failed(reason: e.toString());
    }
  }
}
