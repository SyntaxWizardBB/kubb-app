import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/player/presentation/onboarding_screen.dart';
import 'package:kubb_app/features/player/presentation/profile_screen.dart';
import 'package:kubb_app/features/training/presentation/home_screen.dart';
import 'package:kubb_app/features/training/presentation/sniper_config_screen.dart';
import 'package:kubb_app/features/training/presentation/sniper_session_screen.dart';
import 'package:kubb_app/features/training/presentation/summary_screen.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _ProfileRefresh();
  ref
    ..listen(currentProfileProvider, (_, _) => notifier.notify())
    ..onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final profile = ref.read(currentProfileProvider);
      return profile.when(
        data: (player) {
          final goingToOnboarding = state.matchedLocation == '/onboarding';
          if (player == null && !goingToOnboarding) return '/onboarding';
          if (player != null && goingToOnboarding) return '/';
          return null;
        },
        loading: () => null,
        error: (_, _) => '/onboarding',
      );
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/training/sniper/config',
        builder: (context, state) => const SniperConfigScreen(),
      ),
      GoRoute(
        path: '/training/sniper/session/:id',
        builder: (context, state) =>
            SniperSessionScreen(sessionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/training/summary/:id',
        builder: (context, state) =>
            SummaryScreen(sessionId: state.pathParameters['id']!),
      ),
    ],
  );
});

class _ProfileRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}
