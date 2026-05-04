import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/app/bootstrap.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';

class _FakeAppSettingsNotifier extends AppSettingsNotifier {
  _FakeAppSettingsNotifier(this._initial);

  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;
}

void main() {
  Future<void> pumpWithChoice(WidgetTester tester, ThemeChoice choice) async {
    final player = Player(
      id: 'test-id',
      name: 'Test',
      deviceId: 'test-device',
      createdAt: DateTime.utc(2026),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            () => _FakeAppSettingsNotifier(AppSettings(themeChoice: choice)),
          ),
          profileBootstrapProvider.overrideWith((ref) async => player),
          appBootstrapProvider.overrideWith((ref) async {
            await ref.read(profileBootstrapProvider.future);
            return null;
          }),
          currentProfileProvider.overrideWith(
            (ref) => Stream<Player?>.value(player),
          ),
          displayProfileProvider.overrideWithValue(
            const DisplayProfile(userId: 'test-id', displayName: 'Test'),
          ),
          recentSessionsProvider.overrideWith(
            (ref) => Stream.value(const <RecentSessionView>[]),
          ),
          crashRecoveryProvider.overrideWith((ref) async => null),
        ],
        child: const KubbApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders home greeting in light mode', (tester) async {
    await pumpWithChoice(tester, ThemeChoice.light);

    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Hallo, Test.'), findsOneWidget);
  });

  testWidgets('renders home greeting in dark mode', (tester) async {
    await pumpWithChoice(tester, ThemeChoice.dark);

    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Hallo, Test.'), findsOneWidget);
  });

  testWidgets('renders home greeting in high-contrast mode', (tester) async {
    await pumpWithChoice(tester, ThemeChoice.highContrast);

    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Hallo, Test.'), findsOneWidget);
  });
}
