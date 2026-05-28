import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';

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
  ///
  /// Per ADR-0011 there is no encrypted-backup row to clean up — the
  /// auth.users CASCADE removes user_credentials, user_profiles and
  /// user_inbox_messages in one transaction.
  ///
  /// Order is load-bearing for GDPR Art. 17 (R18-F-03):
  ///   1. Server-side delete — if it fails we abort before touching any
  ///      local state, so a partial delete cannot strand drift rows whose
  ///      cloud counterparts are still alive.
  ///   2. Local drift wipe — truncates every owned table in one
  ///      transaction so no user-generated data survives into the next
  ///      account on the same device.
  ///   3. Keypair clear — last, because losing the private key before the
  ///      server delete completes would lock the user out of retrying
  ///      against the still-extant account.
  Future<void> delete() async {
    state = const AccountDeletionState.deleting();
    final adapter = ref.read(supabaseAuthAdapterProvider);
    final keypair = ref.read(keypairStorageProvider);
    final telemetry = ref.read(authTelemetryProvider);
    final database = ref.read(appDatabaseProvider);
    final userId = adapter.currentState.userId;

    try {
      await adapter.deleteCurrentAccount();
      await database.wipeAll();
      if (userId != null) telemetry.accountDeleteWipedLocal(userId: userId);
      await keypair.clear();
      if (userId != null) telemetry.accountDelete(userId: userId);
      state = const AccountDeletionState.done();
    } on Object catch (e) {
      state = AccountDeletionState.failed(reason: e.toString());
    }
  }
}
