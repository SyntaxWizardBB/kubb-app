import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';

// Resolved once at app start. While pending, KubbApp renders a splash
// instead of the router so the redirect never sees an AsyncLoading
// auth state. Reads the cached auth session so the router can decide
// straight away whether to land on the sign-in screen or the home tab.
final appBootstrapProvider = FutureProvider<CachedAuthSessionData?>(
  (ref) async {
    final dao = ref.read(cachedAuthSessionDaoProvider);
    return dao.current();
  },
);
