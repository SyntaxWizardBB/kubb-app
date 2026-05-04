import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/avatar_circle.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/player/presentation/profile_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class _StubAuthController extends AuthController {
  _StubAuthController(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required DisplayProfile? profile,
    AuthSession session = const AuthSession.signedOut(),
  }) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/profile/edit',
          builder: (_, _) => const Scaffold(body: Text('edit-stub')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          displayProfileProvider.overrideWithValue(profile),
          authControllerProvider.overrideWith(() => _StubAuthController(session)),
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
  }

  testWidgets('shows fallback text when displayProfile is null',
      (tester) async {
    await pump(tester, profile: null);

    expect(find.text('Kein Profil'), findsOneWidget);
    expect(find.byType(AvatarCircle), findsNothing);
    expect(find.text('Bearbeiten'), findsNothing);
  });

  testWidgets(
      'renders avatar, nickname, anonymous badge and edit button for keypair',
      (tester) async {
    const profile = DisplayProfile(
      userId: 'u1',
      displayName: 'Lukas Brosi',
    );
    await pump(
      tester,
      profile: profile,
      session: const AuthSession.keypair(
        userId: 'u1',
        displayName: 'Lukas Brosi',
      ),
    );

    expect(find.byType(AvatarCircle), findsOneWidget);
    expect(find.text('LB'), findsOneWidget);
    expect(find.text('Lukas Brosi'), findsOneWidget);
    expect(find.text('Anonym (Passphrase)'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Bearbeiten'), findsOneWidget);
  });

  testWidgets('renders Google provider badge for OAuth session',
      (tester) async {
    const profile = DisplayProfile(
      userId: 'u1',
      displayName: 'Lukas',
    );
    await pump(
      tester,
      profile: profile,
      session: const AuthSession.oauth(
        userId: 'u1',
        displayName: 'Lukas',
        provider: AuthProvider.google,
      ),
    );

    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Anonym (Passphrase)'), findsNothing);
  });

  testWidgets('renders Apple provider badge for OAuth-Apple session',
      (tester) async {
    const profile = DisplayProfile(
      userId: 'u1',
      displayName: 'Lukas',
    );
    await pump(
      tester,
      profile: profile,
      session: const AuthSession.oauth(
        userId: 'u1',
        displayName: 'Lukas',
        provider: AuthProvider.apple,
      ),
    );

    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Google'), findsNothing);
    expect(find.text('Anonym (Passphrase)'), findsNothing);
  });

  testWidgets(
      'renders anonymous label for AuthSession.anonymous (orElse fallback)',
      (tester) async {
    const profile = DisplayProfile(
      userId: 'u1',
      displayName: 'Lukas',
    );
    await pump(
      tester,
      profile: profile,
      session: const AuthSession.anonymous(userId: 'u1'),
    );

    expect(find.text('Anonym (Passphrase)'), findsOneWidget);
    expect(find.text('Google'), findsNothing);
    expect(find.text('Apple'), findsNothing);
  });

  testWidgets('tapping the edit button navigates to /profile/edit',
      (tester) async {
    const profile = DisplayProfile(
      userId: 'u1',
      displayName: 'Lukas',
    );
    await pump(
      tester,
      profile: profile,
      session: const AuthSession.keypair(
        userId: 'u1',
        displayName: 'Lukas',
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Bearbeiten'));
    await tester.pumpAndSettle();

    expect(find.text('edit-stub'), findsOneWidget);
  });
}
