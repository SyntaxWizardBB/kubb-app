import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/auth/presentation/onboarding_tour.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  Future<GoRouter> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: AuthRoutes.onboardingTour,
      routes: [
        GoRoute(
          path: AuthRoutes.onboardingTour,
          builder: (_, _) => const OnboardingTour(),
        ),
        GoRoute(
          path: AuthRoutes.signIn,
          builder: (_, _) => const Scaffold(body: Text('sign-in-hub')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
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
    return router;
  }

  testWidgets('renders the first slide on entry', (tester) async {
    await pump(tester);

    expect(find.text('Sniper-Training'), findsOneWidget);
    expect(find.text('Finisseur'), findsNothing);
    expect(find.text('Weiter'), findsOneWidget);
    expect(find.text('Überspringen'), findsOneWidget);
  });

  testWidgets('next button advances through all four slides',
      (tester) async {
    await pump(tester);

    expect(find.text('Sniper-Training'), findsOneWidget);

    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Finisseur'), findsOneWidget);

    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Turniere & Ligen'), findsOneWidget);

    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Mit Freunden trainieren'), findsOneWidget);
    // Last slide swaps the CTA label.
    expect(find.text("Los geht's"), findsOneWidget);
    expect(find.text('Weiter'), findsNothing);
  });

  testWidgets('rapid double-tap on next does not skip a slide',
      (tester) async {
    await pump(tester);

    final next = find.text('Weiter');
    await tester.tap(next);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(next);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // Exactly one advance: we are on slide 2 (Finisseur), not slide 3.
    expect(find.text('Finisseur'), findsOneWidget);
    expect(find.text('Turniere & Ligen'), findsNothing);
  });

  testWidgets('dot indicator highlights the current slide',
      (tester) async {
    await pump(tester);

    Iterable<AnimatedContainer> dots() => tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .where((c) => (c.constraints?.maxHeight ?? 0) == 8);

    expect(dots(), hasLength(4));
    final initial = dots().map((d) => d.constraints!.maxWidth).toList();
    expect(initial, [24.0, 8.0, 8.0, 8.0]);

    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    final afterOne = dots().map((d) => d.constraints!.maxWidth).toList();
    expect(afterOne, [8.0, 24.0, 8.0, 8.0]);
  });

  testWidgets('skip routes to sign-in hub and sets onboarding-done flag',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: AuthRoutes.onboardingTour,
      routes: [
        GoRoute(
          path: AuthRoutes.onboardingTour,
          builder: (_, _) => const OnboardingTour(),
        ),
        GoRoute(
          path: AuthRoutes.signIn,
          builder: (_, _) => const Scaffold(body: Text('sign-in-hub')),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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

    expect(container.read<bool>(onboardingDoneProvider), isFalse);

    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();

    expect(find.text('sign-in-hub'), findsOneWidget);
    expect(container.read<bool>(onboardingDoneProvider), isTrue);
  });

  testWidgets('done CTA on last slide routes to sign-in hub',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: AuthRoutes.onboardingTour,
      routes: [
        GoRoute(
          path: AuthRoutes.onboardingTour,
          builder: (_, _) => const OnboardingTour(),
        ),
        GoRoute(
          path: AuthRoutes.signIn,
          builder: (_, _) => const Scaffold(body: Text('sign-in-hub')),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text("Los geht's"));
    await tester.pumpAndSettle();

    expect(find.text('sign-in-hub'), findsOneWidget);
    expect(container.read<bool>(onboardingDoneProvider), isTrue);
  });
}
