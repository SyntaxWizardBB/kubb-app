import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/training/data/training_repository.dart';

/// Loads the active session for the current profile, if any.
///
/// Resolves to `null` when no profile exists or when no session is in
/// `active` status. Kept alive (no autoDispose) so the home screen sees a
/// stable value across rebuilds and the recovery dialog only fires once
/// per app start.
final crashRecoveryProvider = FutureProvider<Session?>((ref) async {
  final profile = ref.watch(displayProfileProvider);
  if (profile == null) return null;
  final repo = ref.watch(trainingRepositoryProvider);
  return repo.loadActiveOrNull(playerId: profile.userId);
});

/// Per-app-start guard so the recovery dialog is shown at most once even
/// when the home screen rebuilds. The home screen flips this flag the
/// first time it sees a non-null active session.
class CrashRecoveryShown extends Notifier<bool> {
  @override
  bool build() => false;

  // Latch helper — positional bool reads naturally at the call site.
  // ignore: avoid_positional_boolean_parameters, use_setters_to_change_properties
  void mark(bool value) => state = value;
}

final crashRecoveryShownProvider =
    NotifierProvider<CrashRecoveryShown, bool>(CrashRecoveryShown.new);
