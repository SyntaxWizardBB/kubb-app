import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/cloud_profile_provider.dart';
import 'package:kubb_app/features/auth/presentation/onboarding_profile_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

import '../../fixtures/auth/fake_cloud_profile_repository.dart';

void main() {
  Future<FakeCloudProfileRepository> pump(WidgetTester tester,
      {Set<String> taken = const {}}) async {
    final fake = FakeCloudProfileRepository()..currentUserId = 'u1';
    fake.takenNicknames.addAll(taken);
    final router = GoRouter(
      initialLocation: '/onboarding/profile',
      routes: [
        GoRoute(
          path: '/onboarding/profile',
          builder: (_, _) => const OnboardingProfileScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('HOME_REACHED'))),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cloudProfileRepositoryProvider.overrideWithValue(fake),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('valid nickname creates the profile and routes home',
      (tester) async {
    final fake = await pump(tester);

    // Button disabled with no input.
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Weiter'),
    );
    expect(button.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'kubb_king');
    await tester.pump(); // apply setState
    await tester.pump(const Duration(milliseconds: 400)); // fire debounce timer
    await tester.pumpAndSettle(); // resolve availability future

    await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await tester.pumpAndSettle();

    expect(fake.createCount, 1);
    expect(fake.storedUserIds, contains('u1'));
    expect(find.text('HOME_REACHED'), findsOneWidget);
  });

  testWidgets('taken nickname surfaces the name-taken hint and blocks submit',
      (tester) async {
    await pump(tester, taken: {'kubb_king'});

    await tester.enterText(find.byType(TextField), 'kubb_king');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Dieser Name ist schon vergeben.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Weiter'),
    );
    expect(button.onPressed, isNull);
  });
}
