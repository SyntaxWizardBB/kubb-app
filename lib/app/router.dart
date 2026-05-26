import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/presentation/account_link_screen.dart';
import 'package:kubb_app/features/auth/presentation/anonymous_signup_flow.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/auth/presentation/delete_account_screen.dart';
import 'package:kubb_app/features/auth/presentation/edit_profile_screen.dart';
import 'package:kubb_app/features/auth/presentation/onboarding_tour.dart';
import 'package:kubb_app/features/auth/presentation/restore_flow.dart';
import 'package:kubb_app/features/auth/presentation/sign_in_screen.dart';
import 'package:kubb_app/features/inbox/presentation/inbox_screen.dart';
import 'package:kubb_app/features/match/presentation/match_await_others_screen.dart';
import 'package:kubb_app/features/match/presentation/match_config_screen.dart';
import 'package:kubb_app/features/match/presentation/match_finished_screen.dart';
import 'package:kubb_app/features/match/presentation/match_lobby_screen.dart';
import 'package:kubb_app/features/match/presentation/match_result_screen.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:kubb_app/features/player/presentation/profile_screen.dart';
import 'package:kubb_app/features/settings/presentation/settings_screen.dart';
import 'package:kubb_app/features/social/presentation/friends_screen.dart';
import 'package:kubb_app/features/social/presentation/groups_screen.dart';
import 'package:kubb_app/features/social/presentation/social_routes.dart';
import 'package:kubb_app/features/stats/presentation/stats_screen.dart';
import 'package:kubb_app/features/team/presentation/team_create_screen.dart';
import 'package:kubb_app/features/team/presentation/team_detail_screen.dart';
import 'package:kubb_app/features/team/presentation/team_invitation_screen.dart';
import 'package:kubb_app/features/team/presentation/team_list_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_bracket_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_conflict_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_detail_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_list_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_match_detail_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_match_list_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_override_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_registration_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_setup_wizard.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_standings_screen.dart';
import 'package:kubb_app/features/training/presentation/finisseur_config_screen.dart';
import 'package:kubb_app/features/training/presentation/finisseur_stick_screen.dart';
import 'package:kubb_app/features/training/presentation/home_screen.dart';
import 'package:kubb_app/features/training/presentation/sniper_config_screen.dart';
import 'package:kubb_app/features/training/presentation/sniper_session_screen.dart';
import 'package:kubb_app/features/training/presentation/summary_screen.dart';
import 'package:kubb_domain/kubb_domain.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRefresh();
  ref
    ..listen(authControllerProvider, (_, _) => notifier.notify())
    ..onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      // Loading without a previous value: stay put. KubbApp renders the
      // splash while appBootstrapProvider resolves, so by the time the
      // router runs for real the session is already known. A lingering
      // AsyncLoading here would mis-redirect to /sign-in for a frame.
      if (!auth.hasValue && !auth.hasError) {
        return null;
      }
      // Error falls back to signedOut so the user lands on /sign-in
      // rather than a stuck protected route.
      final session = auth.hasValue
          ? auth.requireValue
          : const AuthSession.signedOut();
      final loc = state.matchedLocation;
      final inAuthFlow = loc == AuthRoutes.signIn ||
          loc.startsWith('${AuthRoutes.signIn}/') ||
          loc == AuthRoutes.onboardingTour;

      if (!session.isAuthenticated) {
        return inAuthFlow ? null : AuthRoutes.signIn;
      }
      if (loc == AuthRoutes.signIn ||
          loc == AuthRoutes.anonymousSignup ||
          loc == AuthRoutes.restore) {
        return '/';
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AuthRoutes.signIn,
        builder: (_, _) => const SignInScreen(),
      ),
      GoRoute(
        path: AuthRoutes.anonymousSignup,
        builder: (_, _) => const AnonymousSignupFlow(),
      ),
      GoRoute(
        path: AuthRoutes.restore,
        builder: (_, _) => const RestoreFlow(),
      ),
      GoRoute(
        path: AuthRoutes.accountLink,
        builder: (_, _) => const AccountLinkScreen(),
      ),
      GoRoute(
        path: AuthRoutes.deleteAccount,
        builder: (_, _) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: AuthRoutes.onboardingTour,
        builder: (_, _) => const OnboardingTour(),
      ),
      GoRoute(
        path: AuthRoutes.editProfile,
        builder: (_, _) => const EditProfileScreen(),
      ),
      GoRoute(
        path: AuthRoutes.inbox,
        builder: (_, _) => const InboxScreen(),
      ),
      GoRoute(
        path: SocialRoutes.friends,
        builder: (_, _) => const FriendsScreen(),
      ),
      GoRoute(
        path: SocialRoutes.groups,
        builder: (_, _) => const GroupsScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (_, _) => const HomeScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, _) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/stats',
        builder: (_, _) => const StatsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/training/sniper/config',
        builder: (_, _) => const SniperConfigScreen(),
      ),
      GoRoute(
        path: '/training/sniper/session/:id',
        builder: (_, state) =>
            SniperSessionScreen(sessionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/training/finisseur/config',
        builder: (_, _) => const FinisseurConfigScreen(),
      ),
      GoRoute(
        path: '/training/finisseur/session/:id',
        builder: (_, state) =>
            FinisseurStickScreen(sessionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/training/summary/:id',
        builder: (_, state) =>
            SummaryScreen(sessionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: MatchRoutes.newMatch,
        builder: (_, _) => const MatchConfigScreen(),
      ),
      GoRoute(
        path: '${MatchRoutes.lobby}/:id',
        builder: (_, state) =>
            MatchLobbyScreen(matchId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '${MatchRoutes.result}/:id',
        builder: (_, state) =>
            MatchResultScreen(matchId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '${MatchRoutes.awaitOthers}/:id',
        builder: (_, state) =>
            MatchAwaitOthersScreen(matchId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '${MatchRoutes.finished}/:id',
        builder: (_, state) =>
            MatchFinishedScreen(matchId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: TournamentRoutes.list,
        builder: (_, _) => const TournamentListScreen(),
      ),
      GoRoute(
        path: TournamentRoutes.newTournament,
        builder: (_, _) => const TournamentSetupWizard(),
      ),
      GoRoute(
        path: '${TournamentRoutes.detail}/:id',
        builder: (_, state) => TournamentDetailScreen(
          tournamentId: TournamentId(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/tournament/:id/register',
        builder: (_, state) => TournamentRegistrationScreen(
          tournamentId: TournamentId(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/tournament/:id/matches',
        builder: (_, state) => TournamentMatchListScreen(
          tournamentId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId',
        builder: (_, state) => TournamentMatchDetailScreen(
          tournamentId: state.pathParameters['id']!,
          matchId: state.pathParameters['matchId']!,
        ),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId/conflict',
        builder: (_, state) => TournamentConflictScreen(
          tournamentId: state.pathParameters['id']!,
          matchId: state.pathParameters['matchId']!,
        ),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId/override',
        builder: (_, state) => TournamentOverrideScreen(
          tournamentId: state.pathParameters['id']!,
          matchId: state.pathParameters['matchId']!,
        ),
      ),
      GoRoute(
        path: '/tournament/:id/standings',
        builder: (_, state) => TournamentStandingsScreen(
          tournamentId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/tournament/:id/bracket',
        builder: (_, state) => TournamentBracketScreen(
          tournamentId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/teams',
        builder: (_, _) => const TeamListScreen(),
      ),
      GoRoute(
        path: '/teams/new',
        builder: (_, _) => const TeamCreateScreen(),
      ),
      GoRoute(
        path: '/teams/invitations',
        builder: (_, _) => const TeamInvitationScreen(),
      ),
      GoRoute(
        path: '/teams/:id',
        builder: (_, state) => TeamDetailScreen(
          teamId: TeamId(state.pathParameters['id']!),
        ),
      ),
    ],
  );
});

class _AuthRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}
