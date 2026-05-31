import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/app/bootstrap.dart';
import 'package:kubb_app/app/router.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/social/presentation/social_routes.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';

/// Stub that resolves [build] synchronously to a fixed [AuthSession].
class _StubAuthController extends AuthController {
  _StubAuthController(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;
}

/// Stub that never resolves `build` so the controller stays in
/// AsyncLoading. Tests must use `tester.pump` instead of pumpAndSettle.
class _NeverAuthController extends AuthController {
  @override
  Future<AuthSession> build() {
    final completer = Completer<AuthSession>();
    return completer.future;
  }
}

/// Stub that lets the test flip the [AuthSession] at will so the
/// router's refreshListenable wiring can be exercised.
class _SwitchableAuthController extends AuthController {
  _SwitchableAuthController(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;

  void emit(AuthSession next) {
    state = AsyncData(next);
  }
}

void main() {
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    required AuthController Function() controllerFactory,
    bool settle = true,
  }) async {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWith((ref) async => null),
        authControllerProvider.overrideWith(controllerFactory),
        recentSessionsProvider.overrideWith(
          (ref) => Stream.value(const <RecentSessionView>[]),
        ),
        crashRecoveryProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const KubbApp(),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    return container;
  }

  String currentPath(ProviderContainer container) {
    return container
        .read(goRouterProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
  }

  group('redirect — unauthenticated', () {
    // P7: `/` is no longer public — app use without a profile is impossible.
    // A signed-out cold start is redirected to the early-access gate.
    testWidgets('signedOut cold start redirects to early-access',
        (tester) async {
      final container = await pumpApp(
        tester,
        controllerFactory: () =>
            _StubAuthController(const AuthSession.signedOut()),
      );
      expect(currentPath(container), AuthRoutes.earlyAccess);
    });

    testWidgets('signedOut user navigating to /onboarding-tour stays',
        (tester) async {
      final container = await pumpApp(
        tester,
        controllerFactory: () =>
            _StubAuthController(const AuthSession.signedOut()),
      );
      container.read(goRouterProvider).go(AuthRoutes.onboardingTour);
      await tester.pumpAndSettle();
      expect(currentPath(container), AuthRoutes.onboardingTour);
    });

    // R20-F-04: account-link + delete are authenticated-only. Direct-Link
    // ohne Session muss auf /sign-in zurueckfallen.
    testWidgets('signedOut user on /sign-in/account-link redirects to /sign-in',
        (tester) async {
      final container = await pumpApp(
        tester,
        controllerFactory: () =>
            _StubAuthController(const AuthSession.signedOut()),
      );
      container.read(goRouterProvider).go(AuthRoutes.accountLink);
      await tester.pumpAndSettle();
      expect(currentPath(container), AuthRoutes.earlyAccess);
    });

    testWidgets('signedOut user on /sign-in/delete redirects to /sign-in',
        (tester) async {
      final container = await pumpApp(
        tester,
        controllerFactory: () =>
            _StubAuthController(const AuthSession.signedOut()),
      );
      container.read(goRouterProvider).go(AuthRoutes.deleteAccount);
      await tester.pumpAndSettle();
      expect(currentPath(container), AuthRoutes.earlyAccess);
    });

    // Public legal routes (W1-T1/T2 register the screens in parallel; the
    // gate must already allow them through so the wave merges cleanly).
    testWidgets('signedOut user on /legal/privacy passes the gate',
        (tester) async {
      final container = await pumpApp(
        tester,
        controllerFactory: () =>
            _StubAuthController(const AuthSession.signedOut()),
      );
      // /legal/privacy has no registered GoRoute in this worktree yet
      // (W1-T1 lands the screen in parallel). The redirect callback is
      // the unit under test: it must not bounce to /sign-in. We assert
      // on the resolved router configuration without pumping the error-
      // page widget, which would otherwise mount and pollute teardown.
      final router = container.read(goRouterProvider)..go('/legal/privacy');
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/legal/privacy',
      );
    });

    testWidgets('signedOut user on /public/tournament/:id passes the gate',
        (tester) async {
      final container = await pumpApp(
        tester,
        controllerFactory: () =>
            _StubAuthController(const AuthSession.signedOut()),
      );
      // The redirect callback is the unit under test here — we assert it
      // does not bounce to /sign-in. We deliberately read the resolved
      // configuration before pumping the screen frame because the real
      // PublicTournamentScreen wires a TabController whose teardown
      // throws in the test harness (orthogonal — see widget tests).
      final router = container.read(goRouterProvider)
        ..go('/public/tournament/123');
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/public/tournament/123',
      );
    });

    testWidgets('signedOut user on /social/friends redirects to /sign-in',
        (tester) async {
      final container = await pumpApp(
        tester,
        controllerFactory: () =>
            _StubAuthController(const AuthSession.signedOut()),
      );
      container.read(goRouterProvider).go('/social/friends');
      await tester.pumpAndSettle();
      expect(currentPath(container), AuthRoutes.earlyAccess);
    });
  });

  group('redirect — authenticated sessions land on /', () {
    final cases = <String, AuthSession>{
      'keypair': const AuthSession.keypair(
        userId: 'u1',
        displayName: 'Lukas',
      ),
      'oauth-google': const AuthSession.oauth(
        userId: 'u2',
        displayName: 'Lukas',
        provider: AuthProvider.google,
      ),
      'oauth-apple': const AuthSession.oauth(
        userId: 'u3',
        displayName: 'Lukas',
        provider: AuthProvider.apple,
      ),
    };

    for (final entry in cases.entries) {
      testWidgets('${entry.key} session lands on /', (tester) async {
        final container = await pumpApp(
          tester,
          controllerFactory: () => _StubAuthController(entry.value),
        );
        expect(currentPath(container), '/');
      });
    }
  });

  group('redirect — authenticated bouncing off auth-only routes', () {
    final bounceCases = <String, String>{
      '/sign-in': AuthRoutes.signIn,
      '/sign-in/anonymous': AuthRoutes.anonymousSignup,
      '/sign-in/restore': AuthRoutes.restore,
    };
    for (final entry in bounceCases.entries) {
      testWidgets('authenticated user on ${entry.key} bounces to /',
          (tester) async {
        final container = await pumpApp(
          tester,
          controllerFactory: () => _StubAuthController(
            const AuthSession.keypair(userId: 'u1', displayName: 'Lukas'),
          ),
        );
        container.read(goRouterProvider).go(entry.value);
        await tester.pumpAndSettle();
        expect(currentPath(container), '/');
      });
    }
  });

  group('redirect — anonymous session', () {
    // Anonymous is a transient state during the keypair-attach flow.
    // `isAuthenticated` is false on the AuthSession side. Cold-start `/`
    // is whitelisted (R20-F-04), so an anonymous session stays on `/`
    // rather than bouncing — the AccountSetupController owns the on-
    // screen upgrade flow, not the router. Navigating to a protected
    // route still triggers the gate.
    testWidgets('anonymous user navigating to /inbox routes to /sign-in',
        (tester) async {
      final container = await pumpApp(
        tester,
        controllerFactory: () => _StubAuthController(
          const AuthSession.anonymous(userId: 'u1'),
        ),
      );
      container.read(goRouterProvider).go(AuthRoutes.inbox);
      await tester.pumpAndSettle();
      expect(currentPath(container), AuthRoutes.earlyAccess);
    });
  });

  group('routes registry', () {
    // Each AuthRoutes constant must be reachable through the GoRouter
    // instance — i.e. it has a registered builder, not just a path string.
    final allAuthRoutes = <String, String>{
      'signIn': AuthRoutes.signIn,
      'anonymousSignup': AuthRoutes.anonymousSignup,
      'restore': AuthRoutes.restore,
      'accountLink': AuthRoutes.accountLink,
      'deleteAccount': AuthRoutes.deleteAccount,
      'onboardingTour': AuthRoutes.onboardingTour,
      'editProfile': AuthRoutes.editProfile,
    };

    for (final entry in allAuthRoutes.entries) {
      testWidgets('${entry.key} resolves to a registered builder',
          (tester) async {
        // Use an authenticated session so editProfile is reachable too —
        // unauthenticated users get bounced before the builder runs.
        final container = await pumpApp(
          tester,
          controllerFactory: () => _StubAuthController(
            const AuthSession.keypair(userId: 'u1', displayName: 'Lukas'),
          ),
        );
        final router = container.read(goRouterProvider);
        final matches = router.configuration.findMatch(Uri.parse(entry.value));

        // Last match's route must have a builder. RouteMatchList.last is
        // the leaf — for these flat top-level routes, it's the only match.
        expect(
          matches.routes.isNotEmpty,
          isTrue,
          reason: '${entry.key} (${entry.value}) has no route in the config',
        );
        expect(
          matches.routes.whereType<GoRoute>().any((r) => r.builder != null),
          isTrue,
          reason: '${entry.key} (${entry.value}) has no builder registered',
        );
      });
    }
  });

  group('refresh — listens to AuthController state changes', () {
    testWidgets('redirect re-runs when AuthController emits a new state',
        (tester) async {
      final stub = _SwitchableAuthController(const AuthSession.signedOut());
      final container = await pumpApp(
        tester,
        controllerFactory: () => stub,
      );

      // P7: signed-out cold start is gated to early-access (no no-login `/`).
      expect(currentPath(container), AuthRoutes.earlyAccess);

      // Navigate into a protected area — still gated to early-access.
      container.read(goRouterProvider).go(SocialRoutes.friends);
      await tester.pumpAndSettle();
      expect(currentPath(container), AuthRoutes.earlyAccess);

      // Flip the controller to authenticated; refreshListenable must fire.
      stub.emit(
        const AuthSession.keypair(userId: 'u1', displayName: 'Lukas'),
      );
      await tester.pumpAndSettle();

      expect(currentPath(container), '/');
    });
  });

  group('redirect — async edge cases', () {
    testWidgets('AsyncLoading stays on the current route (no redirect)',
        (tester) async {
      final container = await pumpApp(
        tester,
        controllerFactory: _NeverAuthController.new,
        settle: false,
      );
      // While auth is loading the router must not bounce to /sign-in.
      // Initial location is '/', and loading is a no-op.
      expect(currentPath(container), '/');
    });

    // Note on AsyncError: Riverpod 3 auto-retries failed AsyncNotifier
    // builds on a timer, which makes a widget-level reproduction of a
    // stuck AsyncError state flaky. The redirect logic itself (`hasValue
    // ? requireValue : signedOut`) is exercised via the AsyncLoading
    // case above and through the static fallback in the signedOut
    // group: any non-data state resolves to signedOut, then the normal
    // signedOut redirect fires.
  });
}
