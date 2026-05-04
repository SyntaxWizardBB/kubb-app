import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';

// Resolved once at app start. While pending, KubbApp renders a splash
// instead of the router so the redirect never sees an AsyncLoading
// auth state. Reads the cached auth session so the router can decide
// straight away whether to land on the sign-in screen or the home tab.
//
// The profile bootstrap is waited on as a side effect so the router's
// player-fallback (initialProfileProvider) is already populated by the
// time KubbApp swaps the splash for the live router. Drops in M6-T07
// once the router stops watching the player profile.
final appBootstrapProvider = FutureProvider<CachedAuthSessionData?>(
  (ref) async {
    final dao = ref.read(cachedAuthSessionDaoProvider);
    final session = await dao.current();
    // Wait for the profile bootstrap to finish too, so the router's
    // initialProfileProvider fallback is populated by the time KubbApp
    // swaps the splash for the live router.
    await ref.read(profileBootstrapProvider.future);
    return session;
  },
);

// Resolves the player profile once at startup. Feeds the
// LastKnownProfileNotifier below. Will be removed together with
// initialProfileProvider once the router stops watching the player
// profile (M6-T07).
final profileBootstrapProvider = FutureProvider<Player?>((ref) async {
  final repo = ref.read(playerRepositoryProvider);
  return repo.currentOrNull();
});

/// Sticky snapshot of the last successful profile bootstrap result.
///
/// On the first build, mirrors whatever [profileBootstrapProvider]
/// currently holds (null while loading, the player once it resolves).
/// On subsequent emissions, only `AsyncData` updates the state — `loading`
/// and `error` are ignored so a `ref.invalidate` never blanks out the
/// previously-known profile. The router uses this as a fallback when the
/// live `currentProfileProvider` stream has not produced its first frame
/// yet.
///
/// Slated for removal alongside the player-based redirect in M6-T07.
class LastKnownProfileNotifier extends Notifier<Player?> {
  @override
  Player? build() {
    ref.listen<AsyncValue<Player?>>(
      profileBootstrapProvider,
      (_, next) => next.whenData((p) => state = p),
    );
    return ref.read(profileBootstrapProvider).value;
  }
}

final initialProfileProvider =
    NotifierProvider<LastKnownProfileNotifier, Player?>(
  LastKnownProfileNotifier.new,
);
