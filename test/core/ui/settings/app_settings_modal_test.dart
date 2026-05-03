import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/ui/settings/app_settings_modal.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class _FakeSettingsNotifier extends AppSettingsNotifier {
  _FakeSettingsNotifier(this._initial);

  final AppSettings _initial;
  final List<bool> heliCalls = [];
  final List<ThemeChoice> themeCalls = [];

  @override
  Future<AppSettings> build() async => _initial;

  @override
  Future<void> setHeliTracking({required bool value}) async {
    heliCalls.add(value);
    state = AsyncData(state.requireValue.copyWith(heliTracking: value));
  }

  @override
  Future<void> setTheme(ThemeChoice choice) async {
    themeCalls.add(choice);
    state = AsyncData(state.requireValue.copyWith(themeChoice: choice));
  }
}

void main() {
  Future<_FakeSettingsNotifier> pump(
    WidgetTester tester, {
    AppSettings initial = const AppSettings(),
  }) async {
    final fake = _FakeSettingsNotifier(initial);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(() => fake),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const Scaffold(body: AppSettingsModal()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('renders all four rows when settings are loaded', (tester) async {
    await pump(tester);

    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.text('Sprache'), findsOneWidget);
    expect(find.text('Deutsch'), findsOneWidget);
    expect(find.text('Erscheinungsbild'), findsOneWidget);
    expect(find.text('Helikopter zählen'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);
    expect(find.byType(SegmentedButton<ThemeChoice>), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
  });

  testWidgets('tapping the heli switch invokes setHeliTracking', (tester) async {
    final fake = await pump(tester);

    final heliSwitch = find.ancestor(
      of: find.text('Helikopter zählen'),
      matching: find.byType(Row),
    );
    await tester.tap(find.descendant(of: heliSwitch, matching: find.byType(Switch)));
    await tester.pumpAndSettle();

    expect(fake.heliCalls, [false]);
  });
}
