import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/app/bootstrap.dart';
import 'package:kubb_app/app/router.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';

class _StubAuthController extends AuthController {
  _StubAuthController(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;
}

void main() {
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    required AuthSession session,
  }) async {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWith((ref) async => null),
        authControllerProvider.overrideWith(
          () => _StubAuthController(session),
        ),
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
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('signedOut cold start redirects to /sign-in', (tester) async {
    await pumpApp(tester, session: const AuthSession.signedOut());

    // SignInScreen tagline is unique to the auth entry point.
    expect(find.text('Trainings-Tracker für die Wiese'), findsOneWidget);
  });

  testWidgets('keypair session lands on home', (tester) async {
    await pumpApp(
      tester,
      session: const AuthSession.keypair(
        userId: 'u1',
        displayName: 'Lukas',
      ),
    );

    // Greeting is the unique marker of the home scaffold.
    expect(find.text('Hallo, Lukas.'), findsOneWidget);
    expect(find.text('Trainings-Tracker für die Wiese'), findsNothing);
  });

  testWidgets('authenticated nav to /sign-in bounces back to /',
      (tester) async {
    final container = await pumpApp(
      tester,
      session: const AuthSession.keypair(
        userId: 'u1',
        displayName: 'Lukas',
      ),
    );

    container.read(goRouterProvider).go(AuthRoutes.signIn);
    await tester.pumpAndSettle();

    // Redirect must have bounced back to home.
    expect(find.text('Hallo, Lukas.'), findsOneWidget);
    expect(find.text('Trainings-Tracker für die Wiese'), findsNothing);
  });
}
