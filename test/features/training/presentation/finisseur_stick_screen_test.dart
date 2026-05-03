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

  ActiveFinisseurState seed({int currentIndex = 0}) => ActiveFinisseurState(
        sessionId: 'fin-1',
        field: 7,
        base: 3,
        sticks: List<StickResult>.filled(6, const StickResult()),
        currentIndex: currentIndex,
        startedAt: DateTime.utc(2026, 5, 2),
      );

  Future<_FakeNotifier> pump(
    WidgetTester tester, {
    int currentIndex = 0,
  }) async {
    final notifier = _FakeNotifier(seed(currentIndex: currentIndex));
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

  testWidgets('renders stick header and remaining counts', (tester) async {
    await pump(tester);
    expect(find.text('Stock 1 / 6'), findsOneWidget);
    expect(find.text('7'), findsWidgets);
    expect(find.text('3'), findsWidgets);
  });

  testWidgets('tapping a field chip records the value', (tester) async {
    final notifier = await pump(tester);
    await tester.tap(find.widgetWithText(InkWell, '2').first);
    await tester.pumpAndSettle();
    expect(notifier.lastPatch?.fieldHits, 2);
  });

  testWidgets('next button advances to next stick', (tester) async {
    final notifier = await pump(tester);
    await tester.ensureVisible(find.text('Stock 2'));
    await tester.tap(find.widgetWithText(FilledButton, 'Stock 2'));
    await tester.pumpAndSettle();
    expect(notifier.advanced, isTrue);
  });

  testWidgets('last stick shows finish label', (tester) async {
    await pump(tester, currentIndex: 5);
    expect(find.text('Session abschliessen'), findsOneWidget);
  });
}
