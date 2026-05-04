import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/training/application/active_finisseur_notifier.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';
import 'package:kubb_app/features/training/presentation/finisseur_config_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../_helpers/sqlite_open.dart';

class _RecordingNotifier extends ActiveFinisseurNotifier {
  String? lastPlayerId;
  int? lastField;
  int? lastBase;

  @override
  Future<ActiveFinisseurState?> build() async => null;

  @override
  Future<void> startSession({
    required String playerId,
    required int field,
    required int base,
  }) async {
    lastPlayerId = playerId;
    lastField = field;
    lastBase = base;
    state = AsyncData(
      ActiveFinisseurState(
        sessionId: 'finisseur-id',
        field: field,
        base: base,
        sticks: List<StickResult>.filled(6, const StickResult()),
        currentIndex: 0,
        startedAt: DateTime.utc(2026, 5, 2),
      ),
    );
  }
}

void main() {
  registerLinuxSqliteOverride();

  late AppDatabase db;
  late _RecordingNotifier notifier;

  setUp(() async {
    db = await openTestDatabase();
    notifier = _RecordingNotifier();
  });

  tearDown(() async => db.close());

  DisplayProfile profile() =>
      const DisplayProfile(userId: 'p1', displayName: 'Lukas');

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          displayProfileProvider.overrideWithValue(profile()),
          activeFinisseurProvider.overrideWith(() => notifier),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const FinisseurConfigScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Plus button at index 0 belongs to the Field stepper, index 1 to Base.
  Finder fieldPlus() => find.byIcon(LucideIcons.plus).at(0);
  Finder basePlus() => find.byIcon(LucideIcons.plus).at(1);
  Finder fieldMinus() => find.byIcon(LucideIcons.minus).at(0);
  Finder basePlusButton() => find.byIcon(LucideIcons.plus).at(1);

  Future<void> tapStart(WidgetTester tester) async {
    final btn = find.widgetWithText(FilledButton, 'Finisseur starten');
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
  }

  testWidgets('field+ at 5/2 → 6/2 (no swap, room available)',
      (tester) async {
    await pump(tester);
    // Default 7/3 — bring field down to 5 (two minus taps).
    await tester.tap(fieldMinus());
    await tester.pump();
    await tester.tap(fieldMinus());
    await tester.pump();
    // Now 5/3 — tap base- once to land on 5/2.
    await tester.tap(find.byIcon(LucideIcons.minus).at(1));
    await tester.pump();

    await tester.tap(fieldPlus());
    await tester.pumpAndSettle();
    await tapStart(tester);
    expect(notifier.lastField, 6);
    expect(notifier.lastBase, 2);
  });

  testWidgets('field+ at 8/2 swaps to 9/1 (auto-swap)', (tester) async {
    await pump(tester);
    // Default 7/3 → tap field+ once (auto-swap to 8/2).
    await tester.tap(fieldPlus());
    await tester.pumpAndSettle();
    // Now 8/2 → tap field+ again, expect 9/1.
    await tester.tap(fieldPlus());
    await tester.pumpAndSettle();

    await tapStart(tester);
    expect(notifier.lastField, 9);
    expect(notifier.lastBase, 1);
  });

  testWidgets('field+ at 10/0 stays at 10/0 (hard ceiling)',
      (tester) async {
    await pump(tester);
    // Click field+ enough times to climb past base swaps.
    for (var i = 0; i < 10; i++) {
      await tester.tap(fieldPlus());
      await tester.pump();
    }
    // Should now be 10/0. One more tap is a no-op.
    await tester.tap(fieldPlus());
    await tester.pumpAndSettle();

    await tapStart(tester);
    expect(notifier.lastField, 10);
    expect(notifier.lastBase, 0);
  });

  testWidgets('base+ at 5/2 → 5/3 (no swap)', (tester) async {
    await pump(tester);
    // Default 7/3 → set field=5 with two minus taps.
    await tester.tap(fieldMinus());
    await tester.pump();
    await tester.tap(fieldMinus());
    await tester.pump();
    // Drop base to 2.
    await tester.tap(find.byIcon(LucideIcons.minus).at(1));
    await tester.pump();
    // Now 5/2 → base+ → 5/3.
    await tester.tap(basePlus());
    await tester.pumpAndSettle();

    await tapStart(tester);
    expect(notifier.lastField, 5);
    expect(notifier.lastBase, 3);
  });

  testWidgets('base+ at 8/2 swaps to 7/3 (auto-swap)', (tester) async {
    await pump(tester);
    // Default 7/3 → field+ → 8/2 (auto-swap from base).
    await tester.tap(fieldPlus());
    await tester.pumpAndSettle();
    // Now 8/2 → base+ should auto-swap back to 7/3.
    await tester.tap(basePlusButton());
    await tester.pumpAndSettle();

    await tapStart(tester);
    expect(notifier.lastField, 7);
    expect(notifier.lastBase, 3);
  });

  testWidgets('base+ at 5/5 stays at 5/5 (hard cap)', (tester) async {
    await pump(tester);
    // Default 7/3 → field- twice → 5/3.
    await tester.tap(fieldMinus());
    await tester.pump();
    await tester.tap(fieldMinus());
    await tester.pump();
    // Now 5/3 → base+ twice → 5/5.
    await tester.tap(basePlus());
    await tester.pump();
    await tester.tap(basePlus());
    await tester.pumpAndSettle();
    // One more base+ is a no-op (5 is the hard cap).
    await tester.tap(basePlus());
    await tester.pumpAndSettle();

    await tapStart(tester);
    expect(notifier.lastField, 5);
    expect(notifier.lastBase, 5);
  });

  testWidgets('field- at 8/2 → 7/2 (no auto-plus on minus)',
      (tester) async {
    await pump(tester);
    // Default 7/3 → field+ → 8/2.
    await tester.tap(fieldPlus());
    await tester.pumpAndSettle();
    // Now 8/2 → field- → 7/2 (base stays 2, no auto-bump back).
    await tester.tap(fieldMinus());
    await tester.pumpAndSettle();

    await tapStart(tester);
    expect(notifier.lastField, 7);
    expect(notifier.lastBase, 2);
  });
}
