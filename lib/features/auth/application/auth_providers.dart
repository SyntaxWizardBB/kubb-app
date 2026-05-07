import 'package:flutter_riverpod/flutter_riverpod.dart';
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
