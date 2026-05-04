import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/account_status_badge.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class _StubAuthController extends AuthController {
  _StubAuthController(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;
}

void main() {
  Future<void> pump(WidgetTester tester, AuthSession session) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _StubAuthController(session),
          ),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const Scaffold(
            body: Center(child: AccountStatusBadge()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows nothing when session is signed out', (tester) async {
    await pump(tester, const AuthSession.signedOut());

    expect(find.text('Anonym'), findsNothing);
    expect(find.text('Google'), findsNothing);
    expect(find.text('Apple'), findsNothing);
  });

  testWidgets('shows anonym label for keypair session', (tester) async {
    await pump(
      tester,
      const AuthSession.keypair(userId: 'u1', displayName: 'tester'),
    );

    expect(find.text('Anonym'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('shows Google label for oauth-google session', (tester) async {
    await pump(
      tester,
      const AuthSession.oauth(
        userId: 'u2',
        displayName: 'tester',
        provider: AuthProvider.google,
      ),
    );

    expect(find.text('Google'), findsOneWidget);
    expect(find.byIcon(Icons.account_circle_outlined), findsOneWidget);
  });
}
