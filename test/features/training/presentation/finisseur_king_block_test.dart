import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/training/application/active_finisseur_notifier.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';
import 'package:kubb_app/features/training/presentation/finisseur_stick_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

import '../../../_helpers/sqlite_open.dart';

class _FakeNotifier extends ActiveFinisseurNotifier {
  _FakeNotifier(this._state);

  ActiveFinisseurState _state;
  StickResult? lastPatch;
  bool advanced = false;
  bool completed = false;

  @override
  Future<ActiveFinisseurState?> build() async => _state;

  @override
  void updateCurrentStick(StickResult patch) {
    lastPatch = patch;
    _state = _state.copyWithCurrent(patch);
    state = AsyncData(_state);
  }

  @override
  Future<FinisseurAdvanceOutcome> advance() async {
    advanced = true;
    final next = _state.currentIndex + 1;
    _state = _state.copyWithIndex(next);
    state = AsyncData(_state);
    return next >= ActiveFinisseurState.totalSticks
        ? FinisseurAdvanceOutcome.done
        : FinisseurAdvanceOutcome.carryOn;
  }

  @override
  Future<void> complete() async {
    completed = true;
    state = const AsyncData(null);
  }
}

void main() {
  registerLinuxSqliteOverride();

  late AppDatabase db;

  setUp(() async {
    db = await openTestDatabase();
  });

  tearDown(() async => db.close());

  // Seed a state where the player has cleared all field kubbs and only one
  // base kubb remains — i.e. the next hit is the last basekubb.
  ActiveFinisseurState seedLastBase() {
    final sticks = <StickResult>[
      // Stick 0: cleared all 7 field kubbs.
      const StickResult(fieldHits: 7),
      // Stick 1: knocked down 2 of 3 base kubbs.
      const StickResult(eightMHit: true),
      const StickResult(eightMHit: true),
      // Stick 3 = current — only one base kubb left to drop.
      const StickResult(),
      const StickResult(),
      const StickResult(),
    ];
    return ActiveFinisseurState(
      sessionId: 'fin-1',
      field: 7,
      base: 3,
      sticks:sticks,
      currentIndex: 3,
      startedAt: DateTime.utc(2026, 5, 2),
      phase: FinisseurPhase.base,
    );
  }

  // King phase = field+base done, kingThrowTracking on, dedicated stick. The
  // notifier pre-seeds king=hit when the phase opens; mirror that here so
  // tapping Stock-abschliessen behaves like in production.
  ActiveFinisseurState seedKingPhase({int currentIndex = 4}) {
    final sticks = <StickResult>[
      const StickResult(fieldHits: 7),
      const StickResult(eightMHit: true),
      const StickResult(eightMHit: true),
      const StickResult(eightMHit: true),
      const StickResult(king: KingResult(hit: true)),
      const StickResult(),
    ];
    return ActiveFinisseurState(
      sessionId: 'fin-1',
      field: 7,
      base: 3,
      sticks:sticks,
      currentIndex: currentIndex,
      startedAt: DateTime.utc(2026, 5, 2),
      phase: FinisseurPhase.king,
    );
  }

  Future<_FakeNotifier> pump(
    WidgetTester tester, {
    ActiveFinisseurState? initial,
  }) async {
    final notifier = _FakeNotifier(initial ?? seedLastBase());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          activeFinisseurProvider.overrideWith(() => notifier),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const FinisseurStickScreen(sessionId: 'fin-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return notifier;
  }

  testWidgets('last basekubb hit auto-advances even with king tracking on',
      (tester) async {
    final notifier = await pump(tester);
    await tester.tap(find.widgetWithText(InkWell, 'Treffer'));
    await tester.pumpAndSettle();

    // Phase 2 → Phase 3 is now the notifier's job. The last basekubb stays
    // a clean Hit/Miss/Advance interaction; no inline king block.
    expect(notifier.advanced, isTrue);
    expect(notifier.lastPatch?.eightMHit, isTrue);
    expect(notifier.lastPatch?.king, isNull);
  });

  testWidgets('king phase shows only the king block, no hit/miss buttons',
      (tester) async {
    await pump(tester, initial: seedKingPhase());

    // King phase block is the dedicated FinisseurKingDetail card with the
    // position + outcome rows. Hit/Miss/Heli pads must be gone.
    expect(find.text('POSITION'), findsOneWidget);
    expect(find.text('OUTCOME'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Verfehlt'), findsNothing);
    expect(find.text('Stock abschliessen'), findsOneWidget);
  });

  testWidgets('king phase: Stock-abschliessen advances and finishes session',
      (tester) async {
    final notifier = await pump(tester, initial: seedKingPhase());
    // Default king is a hit — pre-seed already in seedKingPhase. Tapping
    // the commit button just advances; no per-tap update is required.
    await tester.tap(find.widgetWithText(FilledButton, 'Stock abschliessen'));
    await tester.pumpAndSettle();

    expect(notifier.advanced, isTrue);
  });

  testWidgets('king miss recorded then advance via Stock-abschliessen',
      (tester) async {
    final notifier = await pump(tester, initial: seedKingPhase());
    await tester.tap(find.widgetWithText(InkWell, 'verfehlt'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Stock abschliessen'));
    await tester.pumpAndSettle();

    expect(notifier.advanced, isTrue);
    expect(notifier.lastPatch?.king?.hit, isFalse);
  });

  testWidgets(
      'last basekubb auto-advances when king tracking is off',
      (tester) async {
    await db.appSettingsDao.save('kingThrowTracking', 'false');
    final notifier = await pump(tester);
    await tester.tap(find.widgetWithText(InkWell, 'Treffer'));
    await tester.pumpAndSettle();

    expect(notifier.advanced, isTrue);
    expect(notifier.lastPatch?.eightMHit, isTrue);
    expect(notifier.lastPatch?.king, isNull);
  });

  testWidgets('non-last basekubb hit auto-advances even with king tracking on',
      (tester) async {
    // Seed two base kubbs remaining, so this hit is NOT the last basekubb.
    final state = ActiveFinisseurState(
      sessionId: 'fin-1',
      field: 7,
      base: 3,
      sticks:<StickResult>[
        const StickResult(fieldHits: 7),
        const StickResult(eightMHit: true),
        const StickResult(),
        const StickResult(),
        const StickResult(),
        const StickResult(),
      ],
      currentIndex: 2,
      startedAt: DateTime.utc(2026, 5, 2),
      phase: FinisseurPhase.base,
    );
    final notifier = await pump(tester, initial: state);
    await tester.tap(find.widgetWithText(InkWell, 'Treffer'));
    await tester.pumpAndSettle();

    expect(notifier.advanced, isTrue);
    expect(notifier.lastPatch?.king, isNull);
  });

  testWidgets('miss in last-basekubb position still auto-advances',
      (tester) async {
    final notifier = await pump(tester);
    await tester.tap(find.widgetWithText(InkWell, 'Verfehlt'));
    await tester.pumpAndSettle();

    expect(notifier.advanced, isTrue);
    expect(notifier.lastPatch?.king, isNull);
    expect(notifier.lastPatch?.eightMHit, isFalse);
  });
}
