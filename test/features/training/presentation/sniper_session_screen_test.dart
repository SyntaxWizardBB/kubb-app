import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_counter.dart';
import 'package:kubb_app/core/ui/widgets/kubb_tap_pad.dart';
import 'package:kubb_app/features/training/application/active_session_notifier.dart';
import 'package:kubb_app/features/training/application/active_session_state.dart';
import 'package:kubb_app/features/training/presentation/sniper_session_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

class _StubSessionNotifier extends ActiveSessionNotifier {
  _StubSessionNotifier(this._initial);
  final ActiveSessionState _initial;
  int hitCalls = 0;
  int missCalls = 0;
  int heliCalls = 0;

  @override
  Future<ActiveSessionState?> build() async => _initial;

  @override
  Future<void> recordHit() async {
    hitCalls++;
    state = AsyncData(_initial.copyWith(hits: _initial.hits + hitCalls));
  }

  @override
  Future<void> recordMiss() async {
    missCalls++;
  }

  @override
  Future<void> recordHeli() async {
    heliCalls++;
  }
}

class _FakeAppSettingsNotifier extends AppSettingsNotifier {
  _FakeAppSettingsNotifier(this._initial);
  final AppSettings _initial;
  final List<bool> eyeCalls = [];

  @override
  Future<AppSettings> build() async => _initial;

  @override
  Future<void> setEyeHidden({required bool value}) async {
    eyeCalls.add(value);
    state = AsyncData(state.requireValue.copyWith(sniperEyeToggleHidden: value));
  }
}

void main() {
  ActiveSessionState defaultState() => ActiveSessionState(
        sessionId: 's1',
        distance: 8,
        hits: 5,
        misses: 3,
        helis: 0,
        startedAt: DateTime.utc(2026, 5, 2),
      );

  Future<(_StubSessionNotifier, _FakeAppSettingsNotifier)> pump(
    WidgetTester tester, {
    AppSettings settings = const AppSettings(),
    ActiveSessionState? sessionState,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = _StubSessionNotifier(sessionState ?? defaultState());
    final fakeSettings = _FakeAppSettingsNotifier(settings);
    final router = GoRouter(
      initialLocation: '/training/sniper/session/s1',
      routes: [
        GoRoute(
          path: '/training/sniper/session/:id',
          builder: (_, state) =>
              SniperSessionScreen(sessionId: state.pathParameters['id']!),
        ),
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
        GoRoute(
          path: '/training/summary/:id',
          builder: (_, state) =>
              Scaffold(body: Text('summary-${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeSessionProvider.overrideWith(() => session),
          appSettingsProvider.overrideWith(() => fakeSettings),
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
    return (session, fakeSettings);
  }

  testWidgets('shows three counters when heli tracking is on', (tester) async {
    await pump(tester);
    expect(find.byType(KubbCounter), findsNWidgets(3));
    expect(find.text('5'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('shows two counters when heli tracking is off', (tester) async {
    await pump(tester, settings: const AppSettings(heliTracking: false));
    expect(find.byType(KubbCounter), findsNWidgets(2));
    expect(find.byType(KubbTapPad), findsNWidgets(4));
  });

  testWidgets('shows six pads when heli tracking is on', (tester) async {
    await pump(tester);
    expect(find.byType(KubbTapPad), findsNWidgets(6));
  });

  testWidgets('hit-plus pad calls recordHit on the notifier', (tester) async {
    final (session, _) = await pump(tester);
    final hitPlus = find.byWidgetPredicate(
      (w) => w is KubbTapPad &&
          w.label == 'Treffer' &&
          w.sign == '+' &&
          w.tone == KubbTapPadTone.hit,
    );
    await tester.tap(hitPlus);
    await tester.pumpAndSettle();
    expect(session.hitCalls, 1);
  });

  testWidgets('eye-toggle button calls setEyeHidden', (tester) async {
    final (_, settings) = await pump(tester);
    await tester.tap(find.byIcon(LucideIcons.eye));
    await tester.pumpAndSettle();
    expect(settings.eyeCalls, [true]);
  });

  testWidgets('counters render dash when eye-toggle is hidden', (tester) async {
    await pump(
      tester,
      settings: const AppSettings(sniperEyeToggleHidden: true),
    );
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('Trefferzahl verdeckt — du wirfst blind.'), findsOneWidget);
  });
}
