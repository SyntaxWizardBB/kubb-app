import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';

part 'account_upgrade_controller.freezed.dart';

@freezed
class AccountUpgradeState with _$AccountUpgradeState {
  const factory AccountUpgradeState.idle() = _UpgradeIdle;
  const factory AccountUpgradeState.linking() = _UpgradeLinking;
  const factory AccountUpgradeState.done() = _UpgradeDone;
  const factory AccountUpgradeState.failed({required String reason}) =
      _UpgradeFailed;
}

final accountUpgradeControllerProvider =
    NotifierProvider<AccountUpgradeController, AccountUpgradeState>(
        AccountUpgradeController.new);

class AccountUpgradeController extends Notifier<AccountUpgradeState> {
  @override
  AccountUpgradeState build() => const AccountUpgradeState.idle();

  Future<void> linkOAuth(AuthProvider provider) async {
    state = const AccountUpgradeState.linking();
    final adapter = ref.read(supabaseAuthAdapterProvider);
    final telemetry = ref.read(authTelemetryProvider);
    try {
      await adapter.linkOAuthToCurrentUser(_mapProvider(provider));
      final userId = adapter.currentState.userId;
      if (userId != null) {
        telemetry.accountUpgrade(
          userId: userId,
          toKind: provider == AuthProvider.google
              ? 'oauth_google'
              : 'oauth_apple',
        );
      }
      state = const AccountUpgradeState.done();
    } on Object catch (e) {
      state = AccountUpgradeState.failed(reason: e.toString());
    }
  }

  AuthOAuthProvider _mapProvider(AuthProvider p) =>
      p == AuthProvider.google
          ? AuthOAuthProvider.google
          : AuthOAuthProvider.apple;
}
