import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/data/connectivity/connectivity_provider.dart';
import 'package:kubb_app/core/data/connectivity/connectivity_service.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/auth/presentation/sign_in_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

import '../../../fixtures/auth/fake_supabase_auth_adapter.dart';

/// Adapter variant that lets the test hold the OAuth call open so the
/// loading state can be observed mid-flight.
class _BlockingOAuthAdapter extends FakeSupabaseAuthAdapter {
  Completer<void>? gate;
  Object? throwOnOAuth;

  @override
  Future<void> signInWithOAuth(AuthOAuthProvider provider) async {
    oauthCount += 1;
    final g = gate;
    if (g != null) {
      await g.future;
    }
    final t = throwOnOAuth;
    if (t != null) {
      throwOnOAuth = null;
      // Test fixture rethrows whatever the test asked us to throw,
      // including domain-specific value types that do not extend Error.
      // ignore: only_throw_errors
      throw t;
    }
  }
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required SupabaseAuthAdapter adapter,
    required ConnectivityService connectivity,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/sign-in',
      routes: [
        GoRoute(
          path: '/sign-in',
          builder: (_, _) => const SignInScreen(),
        ),
        GoRoute(
          path: AuthRoutes.anonymousSignup,
          builder: (_, _) => const Scaffold(body: Text('anon-stub')),
        ),
        GoRoute(
          path: AuthRoutes.restore,
          builder: (_, _) => const Scaffold(body: Text('restore-stub')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseAuthAdapterProvider.overrideWithValue(adapter),
          connectivityServiceProvider.overrideWithValue(connectivity),
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

  testWidgets(
    'shows loading spinner on Google button while OAuth call is in flight',
    (tester) async {
      final adapter = _BlockingOAuthAdapter()..gate = Completer<void>();
      final connectivity = FakeConnectivityService();

      await pump(tester, adapter: adapter, connectivity: connectivity);

      // Sanity: no spinner before the tap.
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('Mit Google anmelden'));
      // Settle the setState that flips _loading; do NOT use
      // pumpAndSettle — the OAuth future is still pending on `gate`.
      await tester.pump();

      expect(adapter.oauthCount, 1);
      // Exactly one spinner — the one inside the active Google button.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Release the gate so the future resolves and the spinner clears.
      adapter.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'surfaces stable error banner when the adapter throws',
    (tester) async {
      final adapter = _BlockingOAuthAdapter()
        ..throwOnOAuth = Exception('raw oauth blew up — do not surface');
      final connectivity = FakeConnectivityService();

      await pump(tester, adapter: adapter, connectivity: connectivity);

      // Banner should not be present before the failing tap.
      expect(
        find.byKey(const ValueKey('signInOauthError')),
        findsNothing,
      );

      await tester.tap(find.text('Mit Google anmelden'));
      await tester.pumpAndSettle();

      // Stable l10n message — never the raw exception text.
      expect(
        find.text('Anmeldung fehlgeschlagen. Versuch es nochmals.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('signInOauthError')),
        findsOneWidget,
      );
      // Raw exception text must not leak into the UI.
      expect(
        find.textContaining('raw oauth blew up'),
        findsNothing,
      );
      // Spinner must clear when the future rejects.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'renders the brand block, OAuth + anonymous buttons, restore link and EST footer in order',
    (tester) async {
      final adapter = _BlockingOAuthAdapter();
      final connectivity = FakeConnectivityService();

      await pump(tester, adapter: adapter, connectivity: connectivity);

      // Brand block — eyebrow, wordmark, tagline.
      expect(find.text('KUBB CLUB'), findsOneWidget);
      expect(find.text('Kubb Club'), findsOneWidget);
      expect(find.text('Trainings-Tracker für die Wiese'), findsOneWidget);

      // Buttons — Google first, Apple skipped on this test platform
      // (kIsWeb = false but Platform.isIOS = false in unit tests), then
      // the divider, anonymous, restore link.
      final google = find.text('Mit Google anmelden');
      final divider = find.text('ODER');
      final anonymous = find.text('Ohne Konto starten (anonym)');
      final restore = find.text('Konto auf neuem Gerät wiederherstellen');
      final foot = find.text('EST. 2025 · DACH');

      expect(google, findsOneWidget);
      expect(divider, findsOneWidget);
      expect(anonymous, findsOneWidget);
      expect(restore, findsOneWidget);
      expect(foot, findsOneWidget);

      // Vertical order Google -> Divider -> Anonymous -> Restore -> Foot.
      double y(Finder f) => tester.getCenter(f).dy;
      expect(y(google) < y(divider), isTrue);
      expect(y(divider) < y(anonymous), isTrue);
      expect(y(anonymous) < y(restore), isTrue);
      expect(y(restore) < y(foot), isTrue);

      // No spinners in the idle layout.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'blocks OAuth dispatch and disables buttons when offline',
    (tester) async {
      final adapter = _BlockingOAuthAdapter();
      final connectivity = FakeConnectivityService(initialOnline: false);

      await pump(tester, adapter: adapter, connectivity: connectivity);

      // Offline banner is visible.
      expect(
        find.textContaining('Du bist offline.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Mit Google anmelden'));
      await tester.pumpAndSettle();

      // No adapter call, no error banner, no spinner.
      expect(adapter.oauthCount, 0);
      expect(
        find.byKey(const ValueKey('signInOauthError')),
        findsNothing,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
