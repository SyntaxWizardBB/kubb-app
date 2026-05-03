import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/training/presentation/widgets/training_sheet.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  Future<void> pumpHost(WidgetTester tester, GoRouter router) async {
    await tester.pumpWidget(
      MaterialApp.router(
        theme: KubbTheme.light(),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }

  GoRouter buildRouter({required ValueChanged<String> onNavigated}) {
    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => TrainingSheet.show(ctx),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/training/sniper/config',
          builder: (context, state) {
            onNavigated('/training/sniper/config');
            return const Scaffold(body: Text('config-route'));
          },
        ),
        GoRoute(
          path: '/training/finisseur/config',
          builder: (context, state) {
            onNavigated('/training/finisseur/config');
            return const Scaffold(body: Text('finisseur-route'));
          },
        ),
      ],
    );
  }

  testWidgets('renders both mode cards plus title', (tester) async {
    await pumpHost(tester, buildRouter(onNavigated: (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Welcher Modus?'), findsOneWidget);
    expect(find.text('Sniper-Training'), findsOneWidget);
    expect(find.text('Finisseur'), findsOneWidget);
    expect(find.text('8 m'), findsOneWidget);
    expect(find.text('7/3'), findsOneWidget);
  });

  testWidgets('tap on sniper card navigates to config route', (tester) async {
    String? navigated;
    await pumpHost(
      tester,
      buildRouter(onNavigated: (route) => navigated = route),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sniper-Training'));
    await tester.pumpAndSettle();

    expect(navigated, '/training/sniper/config');
    expect(find.text('config-route'), findsOneWidget);
  });

  testWidgets('tap on finisseur card navigates to its config route',
      (tester) async {
    String? navigated;
    await pumpHost(
      tester,
      buildRouter(onNavigated: (route) => navigated = route),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finisseur'));
    await tester.pumpAndSettle();

    expect(navigated, '/training/finisseur/config');
    expect(find.text('finisseur-route'), findsOneWidget);
  });
}
