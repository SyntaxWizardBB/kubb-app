// Widget regression for Mängel #2.4 (BH-C-03, W4.1-E):
// The edit-profile form must scroll around the software keyboard so the
// Save button stays reachable when the IME inflates `viewInsets.bottom`.
// We fake a 320px keyboard insert and assert (a) the form is scrollable,
// (b) the Save button is not clipped by the bottom inset.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/cloud_profile_provider.dart';
import 'package:kubb_app/features/auth/presentation/edit_profile_screen.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

import '../../../fixtures/auth/fake_cloud_profile_repository.dart';

Future<void> _pumpWithInsets(
  WidgetTester tester, {
  required double bottomInset,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/edit',
    routes: [
      GoRoute(
        path: '/edit',
        builder: (_, _) => const EditProfileScreen(),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        displayProfileProvider.overrideWithValue(
          const DisplayProfile(
            userId: 'u1',
            displayName: 'wiese-marc',
            avatarColor: '#3a7c2e',
          ),
        ),
        cloudProfileRepositoryProvider
            .overrideWithValue(FakeCloudProfileRepository()),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          viewInsets: EdgeInsets.only(bottom: bottomInset),
        ),
        child: MaterialApp.router(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Mängel #2.4: edit-profile scrolls and Save stays reachable above '
    'a 320px keyboard insert',
    (tester) async {
      await _pumpWithInsets(tester, bottomInset: 320);

      // Body must be a Scrollable so users can reach the Save button
      // when the keyboard eats half the viewport.
      expect(find.byType(SingleChildScrollView), findsWidgets);

      final saveFinder = find.byType(ElevatedButton);
      expect(saveFinder, findsOneWidget);

      // Scroll the form upward so the Save button enters the viewport.
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      final buttonRect = tester.getRect(saveFinder);
      final viewportHeight = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      final keyboardTop = viewportHeight - 320;
      expect(
        buttonRect.bottom <= keyboardTop,
        isTrue,
        reason: 'Save button must sit above the 320px keyboard insert '
            '(bottom=${buttonRect.bottom}, keyboardTop=$keyboardTop)',
      );
    },
  );
}
