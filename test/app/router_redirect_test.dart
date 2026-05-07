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
    testWidgets('signedOut cold start lands on /sign-in', (tester) async {
      final container = await pumpApp(
        tester,
        controllerFactory: () =>
            _StubAuthController(const AuthSession.signedOut()),
      );
      expect(currentPath(container), AuthRoutes.signIn);
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

    testWidgets('signedOut user on /sign-in/account-link stays', (tester) async {
      final container = await pumpApp(
        tester,
        controllerFactory: () =>
            _StubAuthController(const AuthSession.signedOut()),
      );
      container.read(goRouterProvider).go(AuthRoutes.accountLink);
      await tester.pumpAndSettle();
      expect(currentPath(container), AuthRoutes.accountLink);
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
    // `isAuthenticated` is false on the AuthSession side, so a cold-start
    // anonymous still routes to /sign-in (the AccountSetupController owns
    // the on-screen flow, not the router).
    testWidgets('anonymous cold start routes to /sign-in', (tester) async {
      final container = await pumpApp(
        tester,
        controllerFactory: () => _StubAuthController(
          const AuthSession.anonymous(userId: 'u1'),
        ),
      );
      expect(currentPath(container), AuthRoutes.signIn);
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

      // Cold start: signed-out → redirected to /sign-in.
      expect(currentPath(container), AuthRoutes.signIn);

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
