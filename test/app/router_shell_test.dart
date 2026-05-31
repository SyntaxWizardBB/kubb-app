import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/app/bootstrap.dart';
import 'package:kubb_app/app/router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_bottom_nav.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Dummy stateful screen used by the synthetic-shell tests.
///
/// Hat einen lokalen Counter, damit Tab-Persistence-Verhalten
/// beobachtbar wird: bleibt der State erhalten, wenn der Tab kurz
/// gewechselt wurde?
class _CounterScreen extends StatefulWidget {
  const _CounterScreen({required this.label});

  final String label;

  @override
  State<_CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<_CounterScreen>
    with AutomaticKeepAliveClientMixin {
  int _count = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Column(
        children: [
          Text('${widget.label}:$_count'),
          ElevatedButton(
            key: ValueKey('inc-${widget.label}'),
            onPressed: () => setState(() => _count++),
            child: const Text('inc'),
          ),
        ],
      ),
    );
  }
}

class _AuthedAuthController extends AuthController {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.keypair(userId: 'u1', displayName: 'Lukas');
}

class _SignedOutAuthController extends AuthController {
  @override
  Future<AuthSession> build() async => const AuthSession.signedOut();
}

void main() {
  ProviderContainer makeContainer(AuthController Function() factory) {
    return ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWith((ref) async => null),
        authControllerProvider.overrideWith(factory),
        recentSessionsProvider.overrideWith(
          (ref) => Stream.value(const <RecentSessionView>[]),
        ),
        crashRecoveryProvider.overrideWith((ref) async => null),
      ],
    );
  }

  String currentPath(ProviderContainer c) =>
      c.read(goRouterProvider).routerDelegate.currentConfiguration.uri.path;

  group('StatefulShellRoute — configuration', () {
    test('exposes a StatefulShellRoute at top-level with 3 branches', () {
      final container = makeContainer(_AuthedAuthController.new);
      addTearDown(container.dispose);
      final router = container.read(goRouterProvider);
      final shells = router.configuration.routes.whereType<StatefulShellRoute>();
      expect(shells, hasLength(1));
      expect(shells.first.branches, hasLength(3));
    });

    test('each tab root path is reachable through a registered branch', () {
      final container = makeContainer(_AuthedAuthController.new);
      addTearDown(container.dispose);
      final router = container.read(goRouterProvider);
      for (final path in const [
        '/',
        '/training',
        '/stats',
        '/tournament',
        '/profile',
      ]) {
        final matches = router.configuration.findMatch(Uri.parse(path));
        expect(
          matches.routes.whereType<GoRoute>().any((r) => r.builder != null),
          isTrue,
          reason: '$path has no registered builder in the shell',
        );
      }
    });

    test('every tab branch reaches its root through StatefulShellBranch', () {
      final container = makeContainer(_AuthedAuthController.new);
      addTearDown(container.dispose);
      final router = container.read(goRouterProvider);
      final shell =
          router.configuration.routes.whereType<StatefulShellRoute>().first;
      final rootPaths = shell.branches
          .map((b) => b.routes.whereType<GoRoute>().first.path)
          .toList();
      // Order matters: the training hub is the left tab root, home is the
      // middle tab, tournaments the right. Profile and stats are no longer
      // branch roots — they live inside the home / training branches.
      expect(rootPaths, <String>['/training', '/', '/tournament']);
    });
  });

  group('StatefulShellRoute — tab persistence (synthetic shell)', () {
    // Uses a hand-rolled StatefulShellRoute with dummy screens so the
    // test exercises only the shell wiring + KubbBottomNav, not the
    // production feature providers. Mirrors the production setup
    // closely: 3 branches with home in the middle (training, home,
    // tournaments), indexedStack, KubbBottomNav in the scaffold.
    GoRouter buildShellRouter() {
      return GoRouter(
        initialLocation: '/',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => Scaffold(
              body: shell,
              bottomNavigationBar: KubbBottomNav(
                currentIndex: shell.currentIndex,
                onTap: (i) => shell.goBranch(
                  i,
                  initialLocation: i == shell.currentIndex,
                ),
              ),
            ),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/stats',
                    builder: (_, _) => const _CounterScreen(label: 'training'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/',
                    builder: (_, _) => const _CounterScreen(label: 'home'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/tournament',
                    builder: (_, _) =>
                        const _CounterScreen(label: 'tournaments'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    Future<void> pumpRouter(WidgetTester tester, GoRouter router) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
            theme: KubbTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tab tap goes to the branch root', (tester) async {
      final router = buildShellRouter();
      await pumpRouter(tester, router);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/');

      final nav = tester.widget<KubbBottomNav>(find.byType(KubbBottomNav));
      nav.onTap(2);
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/tournament');

      // Home is the middle tab now (index 1).
      nav.onTap(1);
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/');
    });

    testWidgets('tab state persists across switches', (tester) async {
      final router = buildShellRouter();
      await pumpRouter(tester, router);

      // Tap "+" on the home screen → count becomes 1.
      await tester.tap(find.byKey(const ValueKey('inc-home')));
      await tester.pumpAndSettle();
      expect(find.text('home:1'), findsOneWidget);

      // Switch to the training tab (now index 0).
      final nav = tester.widget<KubbBottomNav>(find.byType(KubbBottomNav));
      nav.onTap(0);
      await tester.pumpAndSettle();
      expect(find.text('training:0'), findsOneWidget);

      // Switch back to home (middle tab, index 1) — counter must still read 1
      // (R20-A-13 acceptance: tab state survives switches).
      nav.onTap(1);
      await tester.pumpAndSettle();
      expect(find.text('home:1'), findsOneWidget);
    });

    testWidgets('within-tab push preserves the BottomNav', (tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => Scaffold(
              body: shell,
              bottomNavigationBar: KubbBottomNav(
                currentIndex: shell.currentIndex,
                onTap: (i) => shell.goBranch(i),
              ),
            ),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/stats',
                    builder: (_, _) => const _CounterScreen(label: 'stats'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/',
                    builder: (_, _) => const _CounterScreen(label: 'home'),
                    routes: [
                      GoRoute(
                        path: 'detail',
                        builder: (_, _) =>
                            const _CounterScreen(label: 'detail'),
                      ),
                    ],
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/tournament',
                    builder: (_, _) =>
                        const _CounterScreen(label: 'tournament'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      await pumpRouter(tester, router);

      router.go('/detail');
      await tester.pumpAndSettle();
      expect(find.byType(KubbBottomNav), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/detail');
    });
  });

  group('StatefulShellRoute — runtime', () {
    testWidgets('authenticated cold start mounts the BottomNav', (tester) async {
      final container = makeContainer(_AuthedAuthController.new);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const KubbApp(),
        ),
      );
      // pump a couple of frames; do NOT pumpAndSettle — some downstream
      // providers (Drift, Supabase mocks) spin indefinitely under tests.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(currentPath(container), '/');
      expect(find.byType(KubbBottomNav), findsOneWidget);
    });

    testWidgets('auth-flow routes have NO BottomNav', (tester) async {
      final container = makeContainer(_SignedOutAuthController.new);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const KubbApp(),
        ),
      );
      // Let the bootstrap + redirect cycle settle. Cannot use
      // pumpAndSettle since some feature providers keep timers alive.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // R20-F-04: navigate explicitly into the auth-flow — `/` is now on
      // the public whitelist, so signedOut no longer bounces from cold
      // start. The BottomNav-suppression rule we're guarding here only
      // matters once we reach an actual auth-flow route.
      container.read(goRouterProvider).go(AuthRoutes.signIn);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(currentPath(container), AuthRoutes.signIn);
      // The shell scaffold may still linger in the inactive Navigator
      // stack — what matters is that nothing renders it on screen
      // (zero hit-test surface). `hitTestable()` filters out offstage
      // descendants of inactive routes.
      expect(find.byType(KubbBottomNav).hitTestable(), findsNothing);
    });
  });
}
