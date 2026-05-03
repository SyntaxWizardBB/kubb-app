import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/training/application/active_finisseur_notifier.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';
import 'package:kubb_app/features/training/presentation/finisseur_config_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

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

  Player profile() => Player(
        id: 'p1',
        name: 'Lukas',
        deviceId: 'd1',
        createdAt: DateTime.utc(2026, 5, 2),
      );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          currentProfileProvider.overrideWith((ref) async* {
            yield profile();
          }),
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

  testWidgets('renders default 7/3 preview and labels', (tester) async {
    await pump(tester);
    expect(find.text('7 / 3 · 6 Stöcke'), findsOneWidget);
    expect(find.text('7'), findsWidgets);
    expect(find.text('3'), findsWidgets);
  });

  testWidgets('tapping preset switches to its config', (tester) async {
    await pump(tester);
    await tester.tap(find.text('5/5').first);
    await tester.pumpAndSettle();
    expect(find.text('5 / 5 · 6 Stöcke'), findsOneWidget);
  });

  testWidgets('start button calls startSession with current values',
      (tester) async {
    await pump(tester);
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Finisseur starten'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Finisseur starten'));
    await tester.pumpAndSettle();

    expect(notifier.lastPlayerId, 'p1');
    expect(notifier.lastField, 7);
    expect(notifier.lastBase, 3);
  });

  testWidgets('start button disabled without profile', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          currentProfileProvider.overrideWith(
            (ref) => Stream<Player?>.value(null),
          ),
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

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Finisseur starten'),
    );
    expect(button.onPressed, isNull);
  });
}
