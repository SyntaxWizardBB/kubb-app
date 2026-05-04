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
  Future<bool> advance() async {
    advanced = true;
    final next = _state.currentIndex + 1;
    _state = _state.copyWithIndex(next);
    state = AsyncData(_state);
    return next >= ActiveFinisseurState.totalSticks;
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
      sticks: sticks,
      currentIndex: 3,
      startedAt: DateTime.utc(2026, 5, 2),
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

  testWidgets(
      'last basekubb hit with king tracking on opens king block, no advance',
      (tester) async {
    final notifier = await pump(tester);
    await tester.tap(find.widgetWithText(InkWell, 'Treffer'));
    await tester.pumpAndSettle();

    expect(notifier.advanced, isFalse);
    expect(notifier.lastPatch?.eightMHit, isTrue);
    expect(notifier.lastPatch?.king, isNotNull);
    expect(notifier.lastPatch?.king?.hit, isTrue);
    // King-block fields render their position/outcome row labels.
    expect(find.text('Stock abschliessen'), findsOneWidget);
  });

  testWidgets('king hit confirmed via Stock-abschliessen advances session',
      (tester) async {
    final notifier = await pump(tester);
    await tester.tap(find.widgetWithText(InkWell, 'Treffer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Stock abschliessen'));
    await tester.pumpAndSettle();

    expect(notifier.advanced, isTrue);
    expect(notifier.lastPatch?.king?.hit, isTrue);
  });

  testWidgets('king miss recorded then advance via Stock-abschliessen',
      (tester) async {
    final notifier = await pump(tester);
    await tester.tap(find.widgetWithText(InkWell, 'Treffer'));
    await tester.pumpAndSettle();
    // Toggle king outcome to miss inside the king block (lowercase label).
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
      sticks: <StickResult>[
        const StickResult(fieldHits: 7),
        const StickResult(eightMHit: true),
        const StickResult(),
        const StickResult(),
        const StickResult(),
        const StickResult(),
      ],
      currentIndex: 2,
      startedAt: DateTime.utc(2026, 5, 2),
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
