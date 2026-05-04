import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/app/bootstrap.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';

class _FakeAppSettingsNotifier extends AppSettingsNotifier {
  _FakeAppSettingsNotifier(this._initial);

  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;
}

class _StubAuthController extends AuthController {
  _StubAuthController(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;
}

void main() {
  Future<void> pumpWithChoice(WidgetTester tester, ThemeChoice choice) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            () => _FakeAppSettingsNotifier(AppSettings(themeChoice: choice)),
          ),
          appBootstrapProvider.overrideWith((ref) async => null),
          authControllerProvider.overrideWith(
            () => _StubAuthController(
              const AuthSession.keypair(userId: 'test-id', displayName: 'Test'),
            ),
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
