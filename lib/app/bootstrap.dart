import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';

// Resolved once at app start. While pending, KubbApp renders a splash
// instead of the router so the redirect never sees an AsyncLoading
// profile state.
final appBootstrapProvider = FutureProvider<Player?>((ref) async {
  final repo = ref.read(playerRepositoryProvider);
  return repo.currentOrNull();
});

/// Sticky snapshot of the last successful bootstrap result.
///
/// On the first build, mirrors whatever [appBootstrapProvider] currently
/// holds (null while loading, the player once it resolves). On subsequent
/// emissions, only `AsyncData` updates the state — `loading` and `error`
/// are ignored so a `ref.invalidate` never blanks out the
/// previously-known profile. The router uses this as a fallback when the
/// live `currentProfileProvider` stream has not produced its first frame
/// yet.
class LastKnownProfileNotifier extends Notifier<Player?> {
  @override
  Player? build() {
    ref.listen<AsyncValue<Player?>>(
      appBootstrapProvider,
      (_, next) => next.whenData((p) => state = p),
    );
    // Seed synchronously so the very first read after bootstrap resolves
    // returns the player without waiting for a frame.
    return ref.read(appBootstrapProvider).value;
  }
}

final initialProfileProvider =
    NotifierProvider<LastKnownProfileNotifier, Player?>(
  LastKnownProfileNotifier.new,
);
