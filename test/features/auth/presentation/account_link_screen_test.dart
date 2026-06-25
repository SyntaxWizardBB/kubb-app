import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/account_upgrade_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/presentation/account_link_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class _StubUpgradeController extends AccountUpgradeController {
  _StubUpgradeController(this._initial);
  final AccountUpgradeState _initial;

  @override
  AccountUpgradeState build() => _initial;

  // No-op: tests assert on emitted state, not on the OAuth side-effect.
  @override
  Future<void> linkOAuth(AuthProvider provider) async {
    state = AccountUpgradeState.launching(provider);
  }
}

void main() {
  Future<void> pump(WidgetTester tester, AccountUpgradeState state) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/link',
      routes: [
        GoRoute(
          path: '/link',
          builder: (_, _) => const AccountLinkScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountUpgradeControllerProvider.overrideWith(
            () => _StubUpgradeController(state),
          ),
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

  testWidgets('shows linking spinner only on the active provider',
      (tester) async {
    // Start in idle so the Google button is enabled and tappable.
    await pump(tester, const AccountUpgradeState.idle());

    final googleButton = find.text('Google verknüpfen');
    expect(googleButton, findsOneWidget);

    await tester.tap(googleButton);
    // The stub flips state -> linking; the tap also sets _active locally.
    await tester.pump();

    // Spinner must now render. On Linux/desktop test platform the
    // Apple button is hidden (`_showApple` is false), so we only need
    // to assert that exactly one spinner is visible — the one inside
    // the active Google button.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders success banner when controller emits done',
      (tester) async {
    await pump(tester, const AccountUpgradeState.done());

    expect(find.text('Konto erfolgreich verknüpft.'), findsOneWidget);
    expect(
      find.text('Verknüpfen fehlgeschlagen. Versuch es nochmals.'),
      findsNothing,
    );
  });

  testWidgets('renders error banner when controller emits failed',
      (tester) async {
    await pump(
      tester,
      const AccountUpgradeState.failed(code: 'reconcile_failed'),
    );

    expect(
      find.text('Verknüpfen fehlgeschlagen. Versuch es nochmals.'),
      findsOneWidget,
    );
    expect(find.text('Konto erfolgreich verknüpft.'), findsNothing);
  });

  testWidgets('maps a typed failure code to its specific banner',
      (tester) async {
    await pump(
      tester,
      const AccountUpgradeState.failed(code: 'oauth_subject_in_use'),
    );

    expect(
      find.text(
        'Dieses Google- oder Apple-Konto ist bereits mit einem '
        'anderen Profil verknüpft.',
      ),
      findsOneWidget,
    );
  });
}
