import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/player/data/player_repository.dart';
import 'package:kubb_app/features/player/presentation/onboarding_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

import '../../../_helpers/sqlite_open.dart';

void main() {
  late AppDatabase db;
  late PlayerRepository repo;

  setUpAll(registerLinuxSqliteOverride);

  setUp(() async {
    db = await openTestDatabase();
    repo = PlayerRepository(db.playerDao);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder confirmButton() => find.widgetWithText(FilledButton, 'Weiter');

  bool isEnabled(WidgetTester tester) {
    final button = tester.widget<FilledButton>(confirmButton());
    return button.onPressed != null;
  }

  testWidgets('confirm button disabled when field is empty', (tester) async {
    await pump(tester);

    expect(confirmButton(), findsOneWidget);
    expect(isEnabled(tester), isFalse);
  });

  testWidgets('confirm button enabled when name is valid', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'Lukas');
    await tester.pump();

    expect(isEnabled(tester), isTrue);
  });

  testWidgets('confirm button disabled with whitespace-only name',
      (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();

    expect(isEnabled(tester), isFalse);
  });
}
