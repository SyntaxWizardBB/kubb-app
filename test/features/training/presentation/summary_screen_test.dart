import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/training/data/training_repository.dart';
import 'package:kubb_app/features/training/presentation/summary_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class _FakeRepo implements TrainingRepository {
  String? lastDiscarded;

  @override
  Future<void> discard({required String sessionId}) async {
    lastDiscarded = sessionId;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSettingsNotifier extends AppSettingsNotifier {
  _FakeSettingsNotifier(this._value);
  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;
}

void main() {
  Session session({double distance = 8, int throwTarget = 0}) => Session(
        id: 'sess-1',
        playerId: 'p1',
        kind: 'sniper',
        mode: 'sniper',
        distanceMeters: distance,
        throwTarget: throwTarget == 0 ? null : throwTarget,
        status: 'completed',
        startedAt: DateTime.utc(2026, 5, 2, 10),
        completedAt: DateTime.utc(2026, 5, 2, 10, 0, 30),
      );

  Future<_FakeRepo> pump(
    WidgetTester tester, {
    required SummaryData data,
    AppSettings settings = const AppSettings(),
  }) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeRepo();
    final router = GoRouter(
      initialLocation: '/training/summary/sess-1',
      routes: [
        GoRoute(
          path: '/training/summary/:id',
          builder: (_, state) =>
              SummaryScreen(sessionId: state.pathParameters['id']!),
        ),
        GoRoute(path: '/training', builder: (_, _) => const Scaffold(body: Text('home'))),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          summarySessionProvider('sess-1').overrideWith((_) async => data),
          appSettingsProvider.overrideWith(() => _FakeSettingsNotifier(settings)),
          trainingRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp.router(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('renders 71 % hit rate for 5 hits and 2 misses', (tester) async {
    await pump(
      tester,
      data: SummaryData(session: session(), hits: 5, misses: 2, helis: 0),
    );
    expect(find.text('71 %'), findsOneWidget);
  });

  testWidgets('hides Heli row when heli tracking is off', (tester) async {
    await pump(
      tester,
      data: SummaryData(session: session(), hits: 5, misses: 2, helis: 0),
      settings: const AppSettings(heliTracking: false),
    );
    expect(find.text('Heli'), findsNothing);
    expect(find.text('Treffer'), findsOneWidget);
  });

  testWidgets('shows Heli row when heli tracking is on', (tester) async {
    await pump(
      tester,
      data: SummaryData(session: session(), hits: 5, misses: 2, helis: 1),
    );
    expect(find.text('Heli'), findsOneWidget);
  });

  testWidgets('renders dash for zero-throw session', (tester) async {
    await pump(
      tester,
      data: SummaryData(session: session(), hits: 0, misses: 0, helis: 0),
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('discard button calls repo.discard with the session id',
      (tester) async {
    final repo = await pump(
      tester,
      data: SummaryData(session: session(), hits: 5, misses: 2, helis: 0),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Verwerfen'));
    await tester.pumpAndSettle();
    expect(repo.lastDiscarded, 'sess-1');
  });
}
