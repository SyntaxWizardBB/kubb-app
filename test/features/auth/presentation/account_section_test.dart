import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/presentation/account_section.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class _StubAuthController extends AuthController {
  _StubAuthController(this._initial);
  final AuthSession _initial;
  int signOutCallCount = 0;

  @override
  Future<AuthSession> build() async => _initial;

  @override
  Future<void> signOut() async {
    signOutCallCount++;
    state = const AsyncData(AuthSession.signedOut());
  }
}

void main() {
  Future<_StubAuthController> pump(
    WidgetTester tester,
    AuthSession session,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final stub = _StubAuthController(session);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(child: AccountSection()),
          ),
        ),
        GoRoute(
          path: '/sign-in/account-link',
          builder: (_, _) =>
              const Scaffold(body: Text('account-link-stub')),
        ),
        GoRoute(
          path: '/sign-in/passphrase-change',
          builder: (_, _) =>
              const Scaffold(body: Text('passphrase-change-stub')),
        ),
        GoRoute(
          path: '/sign-in/delete',
          builder: (_, _) => const Scaffold(body: Text('delete-stub')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => stub),
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
    return stub;
  }

  AppLocalizations l10nOf(WidgetTester tester) {
    return AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
  }

  testWidgets('renders nothing when session is signed out', (tester) async {
    await pump(tester, const AuthSession.signedOut());
    final l10n = l10nOf(tester);

    expect(find.text(l10n.authAccountSectionLabel), findsNothing);
    expect(find.text(l10n.authAccountSignOutLabel), findsNothing);
  });

  testWidgets('shows link-account row only for anonymous keypair sessions',
      (tester) async {
    await pump(
      tester,
      const AuthSession.keypair(userId: 'u1', displayName: 'wiese-marc'),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.authAccountSectionLabel), findsOneWidget);
    expect(find.text(l10n.authAccountLinkLabel), findsOneWidget);
    expect(find.text(l10n.authAccountPassphraseLabel), findsOneWidget);
    expect(find.text(l10n.authAccountProviderAnonymous), findsOneWidget);
    expect(find.text(l10n.authAccountSignOutLabel), findsOneWidget);
    expect(find.text(l10n.authAccountDeleteLabel), findsOneWidget);
  });

  testWidgets(
      'hides link-account and passphrase rows for oauth without keypair fallback',
      (tester) async {
    await pump(
      tester,
      const AuthSession.oauth(
        userId: 'u1',
        displayName: 'wiese-marc',
        provider: AuthProvider.google,
      ),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.authAccountLinkLabel), findsNothing);
    expect(find.text(l10n.authAccountPassphraseLabel), findsNothing);
    expect(find.text(l10n.authAccountProviderGoogle), findsOneWidget);
    expect(find.text(l10n.authAccountSignOutLabel), findsOneWidget);
    expect(find.text(l10n.authAccountDeleteLabel), findsOneWidget);
  });

  testWidgets('shows passphrase row for oauth with keypair fallback',
      (tester) async {
    await pump(
      tester,
      const AuthSession.oauth(
        userId: 'u1',
        displayName: 'wiese-marc',
        provider: AuthProvider.google,
        hasKeypairFallback: true,
      ),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.authAccountPassphraseLabel), findsOneWidget);
    expect(find.text(l10n.authAccountLinkLabel), findsNothing);
    expect(find.text(l10n.authAccountProviderGoogle), findsOneWidget);
  });

  testWidgets('tapping sign-out invokes signOut on AuthController',
      (tester) async {
    final stub = await pump(
      tester,
      const AuthSession.keypair(userId: 'u1', displayName: 'wiese-marc'),
    );
    final l10n = l10nOf(tester);

    expect(stub.signOutCallCount, 0);

    await tester.tap(find.text(l10n.authAccountSignOutLabel));
    await tester.pumpAndSettle();

    expect(stub.signOutCallCount, 1);
  });
}
