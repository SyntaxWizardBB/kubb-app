import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/presentation/onboarding_tour.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class _StubAuthController extends AuthController {
  _StubAuthController(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;
}

void main() {
  Future<void> pump(WidgetTester tester, AuthSession session) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const OnboardingTour(),
        ),
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _StubAuthController(session),
          ),
        ],
        child: MaterialApp.router(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('rapid double-tap on next does not advance two pages',
      (tester) async {
    await pump(
      tester,
      const AuthSession.keypair(userId: 'u1', displayName: 'tester'),
    );

    final next = find.text('Weiter');
    expect(next, findsOneWidget);

    await tester.tap(next);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(next);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // After settling, exactly one advance must have happened. Page 1
    // shows the modes title; page 2 would already show the soon
    // headline. Both strings are unique to their slide.
    expect(find.text('Trainingsmodi'), findsOneWidget);
    expect(find.text('Bald verfügbar'), findsNothing);
  });
}
