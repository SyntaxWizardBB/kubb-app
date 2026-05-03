import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/training/application/active_session_notifier.dart';
import 'package:kubb_app/features/training/application/active_session_state.dart';
import 'package:kubb_app/features/training/presentation/sniper_config_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

import '../../../_helpers/sqlite_open.dart';

class _RecordingNotifier extends ActiveSessionNotifier {
  String? lastPlayerId;
  double? lastDistance;
  int? lastThrowTarget;

  @override
  Future<ActiveSessionState?> build() async => null;

  @override
  Future<void> startSession({
    required String playerId,
    required double distance,
    int? throwTarget,
  }) async {
    lastPlayerId = playerId;
    lastDistance = distance;
    lastThrowTarget = throwTarget;
    state = AsyncData(
      ActiveSessionState(
        sessionId: 'session-id',
        distance: distance,
        throwTarget: throwTarget,
        hits: 0,
        misses: 0,
        helis: 0,
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
          activeSessionProvider.overrideWith(() => notifier),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const SniperConfigScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders default distance of 8.0 m', (tester) async {
    await pump(tester);
    expect(find.text('8.0 m'), findsOneWidget);
    expect(find.text('kein Ziel'), findsOneWidget);
  });

  testWidgets('slider movement updates distance display', (tester) async {
    await pump(tester);
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(6.5);
    await tester.pumpAndSettle();
    expect(find.text('6.5 m'), findsOneWidget);
  });

  testWidgets('selecting target chip updates throw target', (tester) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '50'));
    await tester.pumpAndSettle();
    expect(find.text('50'), findsWidgets);
  });

  testWidgets('start button calls startSession with config values',
      (tester) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '100'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sniper starten'));
    await tester.pumpAndSettle();

    expect(notifier.lastPlayerId, 'p1');
    expect(notifier.lastDistance, 8.0);
    expect(notifier.lastThrowTarget, 100);
  });
}
