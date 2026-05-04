import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';

/// Read-only display values for the active user. Sourced from the
/// cached_auth_session metadata so the UI can render without hitting
/// Supabase. Lives in `player/application/` because the historical
/// player feature owns the "display the current user" surface.
class DisplayProfile {
  const DisplayProfile({
    required this.userId,
    required this.displayName,
    this.avatarColor,
  });

  final String userId;
  final String displayName;
  final String? avatarColor;
}

final displayProfileProvider = Provider<DisplayProfile?>((ref) {
  return ref.watch(authControllerProvider).maybeWhen(
        data: (session) => switch (session) {
          KeypairSession(:final userId, :final displayName, :final avatarColor) =>
            DisplayProfile(
              userId: userId,
              displayName: displayName,
              avatarColor: avatarColor,
            ),
          OAuthSession(:final userId, :final displayName, :final avatarColor) =>
            DisplayProfile(
              userId: userId,
              displayName: displayName,
              avatarColor: avatarColor,
            ),
          _ => null,
        },
        orElse: () => null,
      );
});
