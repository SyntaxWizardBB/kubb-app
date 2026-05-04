import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';

/// Computed views over [authControllerProvider]. Live in their own
/// file so widgets can read just one provider without pulling in the
/// full controller surface.

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authControllerProvider).maybeWhen(
        data: (session) => session.userId,
        orElse: () => null,
      );
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authControllerProvider).maybeWhen(
        data: (session) => session.isAuthenticated,
        orElse: () => false,
      );
});

final isAnonymousKeypairProvider = Provider<bool>((ref) {
  return ref.watch(authControllerProvider).maybeWhen(
        data: (session) => session.isAnonymousKeypair,
        orElse: () => false,
      );
});

/// `updated_at` of the active user's keypair-backup row, or `null` if
/// no row exists yet. Returns `null` for non-keypair sessions so
/// consumers can simply treat null as "do not show backup hint".
final lastKeypairBackupAtProvider = FutureProvider<DateTime?>((ref) async {
  final isKeypair = ref.watch(isAnonymousKeypairProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (!isKeypair || userId == null) {
    return null;
  }
  return ref.read(keypairBackupRepositoryProvider).backupTimestamp(
        userId: userId,
      );
});
