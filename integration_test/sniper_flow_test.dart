// Integration test for the Sniper-Training MVP happy path.
//
// Requires a Flutter device or emulator — `flutter test` (the unit-test
// runner) cannot drive this. Run via:
//   flutter test integration_test/sniper_flow_test.dart -d <device>
// The CI/dev box without a simulator skips this file; the test stays as
// a regression asset for the Android build pipeline.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('de');
  });

  testWidgets('full sniper flow — onboarding → session → summary → recent',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement('PRAGMA foreign_keys = ON');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const KubbApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Onboarding — type the name, confirm.
    await tester.enterText(find.byType(TextField), 'Lukas');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    expect(find.text('Hallo, Lukas.'), findsOneWidget);

    // Open training sheet, pick sniper.
    await tester.tap(find.text('Training'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sniper-Training'));
    await tester.pumpAndSettle();

    // Config — leave defaults, start.
    await tester.tap(find.text('Sniper starten'));
    await tester.pumpAndSettle();

    // Session — three hits.
    final hitButton = find.text('Treffer');
    expect(hitButton, findsWidgets);
    for (var i = 0; i < 3; i++) {
      await tester.tap(hitButton.first);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // End session → summary.
    await tester.tap(find.text('Session beenden'));
    await tester.pumpAndSettle();

    expect(find.text('100 %'), findsOneWidget);

    // Save → home.
    await tester.tap(find.text('Speichern').first);
    await tester.pumpAndSettle();

    // Recent section now has one entry.
    expect(find.text('ZULETZT'), findsOneWidget);
    expect(find.text('SNIPER'), findsOneWidget);
  });
}
