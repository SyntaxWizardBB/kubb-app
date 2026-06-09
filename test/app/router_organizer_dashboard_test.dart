import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/app/bootstrap.dart';
import 'package:kubb_app/app/router.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/tournament/presentation/organizer_dashboard_detail_screen.dart';
import 'package:kubb_app/features/tournament/presentation/organizer_dashboard_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_detail_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';

/// Resolves [build] synchronously to a fixed authenticated [AuthSession] so
/// the protected tournament branch is reachable.
class _StubAuthController extends AuthController {
  _StubAuthController(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;
}

void main() {
  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWith((ref) async => null),
        authControllerProvider.overrideWith(
          () => _StubAuthController(
            const AuthSession.keypair(userId: 'u1', displayName: 'Lukas'),
          ),
        ),
        recentSessionsProvider.overrideWith(
          (ref) => Stream.value(const <RecentSessionView>[]),
        ),
        crashRecoveryProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const KubbApp(),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('organizer dashboard routing — static before dynamic', () {
    testWidgets(
        '/tournament/dashboard resolves to the overview, NOT detail(id=dashboard)',
        (tester) async {
      final container = await pumpApp(tester);
      final router = container.read(goRouterProvider);

      // Inspect the matched route config: the static overview route must win.
      final matches =
          router.configuration.findMatch(Uri.parse(TournamentRoutes.dashboard));
      final leaf = matches.routes.whereType<GoRoute>().last;
      expect(leaf.path, TournamentRoutes.dashboard);
      // It must NOT be the dynamic detail route capturing :id == 'dashboard'.
      expect(leaf.path, isNot('/tournament/:id'));
      // No `:id == 'dashboard'` path parameter leaked through.
      expect(matches.pathParameters['id'], isNull);

      // And it actually renders the overview screen, not the detail screen.
      router.go(TournamentRoutes.dashboard);
      await tester.pumpAndSettle();
      expect(find.byType(OrganizerDashboardScreen), findsOneWidget);
      expect(find.byType(TournamentDetailScreen), findsNothing);
    });

    testWidgets(
        '/tournament/<id>/dashboard resolves to the detail with extracted id',
        (tester) async {
      final container = await pumpApp(tester);
      final router = container.read(goRouterProvider);

      final matches = router.configuration
          .findMatch(Uri.parse(TournamentRoutes.dashboardDetail('abc-123')));
      final leaf = matches.routes.whereType<GoRoute>().last;
      expect(leaf.path, '/tournament/:id/dashboard');
      expect(matches.pathParameters['id'], 'abc-123');

      router.go(TournamentRoutes.dashboardDetail('abc-123'));
      await tester.pumpAndSettle();
      final screen = tester.widget<OrganizerDashboardDetailScreen>(
        find.byType(OrganizerDashboardDetailScreen),
      );
      expect(screen.tournamentId.value, 'abc-123');
    });

    test('dashboardDetail composes /tournament/<id>/dashboard', () {
      expect(TournamentRoutes.dashboard, '/tournament/dashboard');
      expect(
        TournamentRoutes.dashboardDetail('xyz'),
        '/tournament/xyz/dashboard',
      );
    });
  });
}
