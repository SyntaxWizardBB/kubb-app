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

// Synchronous handle to the bootstrap result. Reading this before the
// bootstrap has resolved throws — KubbApp is the gate that guarantees
// it has.
final initialProfileProvider = Provider<Player?>((ref) {
  return ref.watch(appBootstrapProvider).requireValue;
});
