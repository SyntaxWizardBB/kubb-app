import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/app/public_router_shell.dart';
import 'package:kubb_app/core/ui/widgets/kubb_bottom_nav.dart';
import 'package:kubb_app/features/achievements/presentation/achievements_screen.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/presentation/account_link_screen.dart';
import 'package:kubb_app/features/auth/presentation/anonymous_signup_flow.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/auth/presentation/delete_account_screen.dart';
import 'package:kubb_app/features/auth/presentation/early_access_entry_screen.dart';
import 'package:kubb_app/features/auth/presentation/edit_profile_screen.dart';
import 'package:kubb_app/features/auth/presentation/onboarding_tour.dart';
import 'package:kubb_app/features/auth/presentation/restore_flow.dart';
import 'package:kubb_app/features/auth/presentation/sign_in_screen.dart';
import 'package:kubb_app/features/club/presentation/club_add_member_screen.dart';
import 'package:kubb_app/features/club/presentation/club_create_screen.dart';
import 'package:kubb_app/features/club/presentation/club_detail_screen.dart';
import 'package:kubb_app/features/club/presentation/clubs_screen.dart';
import 'package:kubb_app/features/inbox/presentation/archive_screen.dart';
import 'package:kubb_app/features/inbox/presentation/inbox_screen.dart';
import 'package:kubb_app/features/legal/presentation/imprint_screen.dart';
import 'package:kubb_app/features/legal/presentation/privacy_policy_screen.dart';
import 'package:kubb_app/features/match/presentation/match_await_others_screen.dart';
import 'package:kubb_app/features/match/presentation/match_config_screen.dart';
import 'package:kubb_app/features/match/presentation/match_finished_screen.dart';
import 'package:kubb_app/features/match/presentation/match_lobby_screen.dart';
import 'package:kubb_app/features/match/presentation/match_result_screen.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:kubb_app/features/player/presentation/profile_screen.dart';
import 'package:kubb_app/features/settings/presentation/settings_screen.dart';
import 'package:kubb_app/features/social/presentation/friend_profile_screen.dart';
import 'package:kubb_app/features/social/presentation/friends_screen.dart';
import 'package:kubb_app/features/social/presentation/social_routes.dart';
import 'package:kubb_app/features/stats/presentation/stats_screen.dart';
import 'package:kubb_app/features/team/presentation/team_add_player_screen.dart';
import 'package:kubb_app/features/team/presentation/team_create_screen.dart';
import 'package:kubb_app/features/team/presentation/team_detail_screen.dart';
import 'package:kubb_app/features/team/presentation/team_edit_screen.dart';
import 'package:kubb_app/features/team/presentation/team_invitation_screen.dart';
import 'package:kubb_app/features/team/presentation/team_list_screen.dart';
import 'package:kubb_app/features/tournament/presentation/public/public_match_screen.dart';
import 'package:kubb_app/features/tournament/presentation/public/public_tournament_screen.dart';
import 'package:kubb_app/features/tournament/presentation/register_team_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_bracket_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_conflict_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_detail_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_edit_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_hub_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_list_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_live_dashboard_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_match_detail_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_match_list_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_mercenary_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_override_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_past_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_ranking_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_registration_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_registrations_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_seeding_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_setup_wizard.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_shootout_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_standings_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_stats_screen.dart';
import 'package:kubb_app/features/training/presentation/finisseur_config_screen.dart';
import 'package:kubb_app/features/training/presentation/finisseur_stick_screen.dart';
import 'package:kubb_app/features/training/presentation/home_screen.dart';
import 'package:kubb_app/features/training/presentation/my_training_sessions_screen.dart';
import 'package:kubb_app/features/training/presentation/sniper_config_screen.dart';
import 'package:kubb_app/features/training/presentation/sniper_session_screen.dart';
import 'package:kubb_app/features/training/presentation/summary_screen.dart';
import 'package:kubb_app/features/training/presentation/training_hub_screen.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Branch-Indizes des [StatefulShellRoute.indexedStack].
///
/// Spiegelt die Tab-Reihenfolge der [KubbBottomNav] (Home bewusst mittig).
/// Aenderungen hier muessen mit den Branches in [goRouterProvider] und den
/// Items der [KubbBottomNav] synchron bleiben. Profil ist kein Tab mehr —
/// `/profile` lebt jetzt im Home-Branch und wird ueber den AppBar-Avatar
/// erreicht.
abstract final class ShellTab {
  static const training = 0;
  static const home = 1;
  static const tournaments = 2;
}

/// Whitelist exact-match routes reachable without an authenticated
/// session. Anything not on this list (or matching [_publicPrefixes])
/// requires `session.isAuthenticated == true`.
///
/// Hintergrund (R20-F-04): die alte `inAuthFlow`-Logik war eine
/// Blacklist, die alles unter `/sign-in/*` als public behandelt hat.
/// Direct-Links auf `/sign-in/account-link` und `/sign-in/delete`
/// waren damit auch fuer signedOut-User erreichbar — beide Screens
/// sind aber nur fuer eine bestehende Session sinnvoll und konnten
/// crashen oder Account-Operationen auf einer Anon-Session ausloesen.
// P7: '/' is no longer public — app use without a login/profile is not
// possible. Unauthenticated users are sent to the early-access gate; the
// sign-in / restore / signup routes stay reachable so accounts can be created
// or recovered.
const _publicRoutes = <String>{
  '/sign-in',
  '/sign-in/early-access',
  '/sign-in/anonymous',
  '/sign-in/restore',
  '/onboarding-tour',
  '/legal/privacy',
  '/legal/imprint',
};

/// Whitelist prefix-match routes — used for dynamic spectator URLs
/// like `/public/tournament/:id` (ADR-0026) where the suffix is
/// variable.
const _publicPrefixes = <String>{
  '/public/',
};

final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRefresh();
  ref
    ..listen(authControllerProvider, (_, _) => notifier.notify())
    ..onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    // Safety net: an unknown/misconfigured route renders a visible error
    // page with a way home, instead of a silent blank screen (which is how
    // the missing team-registration route used to fail).
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Seite nicht gefunden')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.error?.toString() ?? 'Unbekannte Route: ${state.uri}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Zur Startseite'),
              ),
            ],
          ),
        ),
      ),
    ),
    redirect: (context, state) {
      final loc = state.matchedLocation;
      // Public spectator routes (M4.2 / ADR-0026) bypass the auth gate
      // entirely — der anon-`apikey` aus dem Standard-SupabaseClient
      // reicht fuer die `public_*_get`-RPCs (Strategie A, kein
      // signInAnonymously()-Round-Trip mehr). Prefix-Match, weil die
      // Suffixe dynamisch sind (`/public/tournament/:id`).
      if (_publicPrefixes.any(loc.startsWith)) {
        return null;
      }
      // Legal pages (DSGVO Art. 13/14) muessen ohne Auth erreichbar
      // sein — sowohl fuer Pre-Sign-Up-Aufrufer als auch fuer den Store-
      // Review.
      if (state.matchedLocation.startsWith('/legal/')) {
        return null;
      }
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

      if (!session.isAuthenticated) {
        // Whitelist: nur explizit oeffentliche Routen duerfen ohne
        // Session passieren (R20-F-04). Alles andere — inklusive
        // `/sign-in/account-link` und `/sign-in/delete` — wird auf
        // den Sign-In-Screen umgeleitet.
        // Unauthenticated → land on the early-access gate (the entry point
        // for creating a profile); restore + sign-in stay reachable from there.
        return _publicRoutes.contains(loc) ? null : AuthRoutes.earlyAccess;
      }
      if (loc == AuthRoutes.signIn ||
          loc == AuthRoutes.earlyAccess ||
          loc == AuthRoutes.anonymousSignup ||
          loc == AuthRoutes.restore) {
        return '/';
      }
      return null;
    },
    routes: <RouteBase>[
      // ── Public / auth flows — OUTSIDE the BottomNav shell ──
      GoRoute(
        path: AuthRoutes.signIn,
        builder: (_, _) => const SignInScreen(),
      ),
      GoRoute(
        path: AuthRoutes.earlyAccess,
        builder: (_, _) => const EarlyAccessEntryScreen(),
      ),
      GoRoute(
        path: AuthRoutes.anonymousSignup,
        // The validated early-access code arrives via `extra`. Reaching this
        // route without it (e.g. a deep link) lands on an empty code, which
        // keypair_register rejects — the proper entry is the early-access gate.
        builder: (_, state) =>
            AnonymousSignupFlow(earlyAccessCode: (state.extra as String?) ?? ''),
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
        path: '/legal/privacy',
        builder: (_, _) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: '/legal/imprint',
        builder: (_, _) => const ImprintScreen(),
      ),
      GoRoute(
        path: '/public/tournament/:id',
        builder: (_, state) => PublicRouterShell(
          child: PublicTournamentScreen(
            tournamentId: TournamentId(state.pathParameters['id']!),
          ),
        ),
      ),
      GoRoute(
        path: '/public/match/:matchId',
        builder: (_, state) => PublicRouterShell(
          child: PublicMatchScreen(
            matchId: state.pathParameters['matchId']!,
          ),
        ),
      ),

      // ── Authenticated shell with persistent BottomNav ──
      // StatefulShellRoute.indexedStack hosts one Navigator per branch
      // (R20-A-13). Pushing within a tab keeps the other tabs' stacks
      // intact, and switching tabs restores them rather than rebuilding.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _ShellScaffold(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          // Branch 0 — Training-Tab. Der /training-Hub ist der Tab-Root; die
          // Solo-/Match-Flows und das Stats-Screen leben im selben Branch,
          // damit ein Hub-Tap (context.push) auf dem Training-Stack bleibt
          // und der BottomNav-Index nicht wegspringt.
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/training',
                builder: (_, _) => const TrainingHubScreen(),
              ),
              GoRoute(
                path: '/stats',
                builder: (_, _) => const StatsScreen(),
              ),
              // Freunde lebt seit P7 als Kachel im Training-Hub; die Route
              // liegt deshalb in diesem Branch, damit ein Hub-Tap auf dem
              // Training-Stack bleibt.
              GoRoute(
                path: SocialRoutes.friends,
                builder: (_, _) => const FriendsScreen(),
              ),
              GoRoute(
                // Freundesprofil + Trainings-Statistik (P2). nickname kommt
                // über `extra` für den Header.
                path: '/social/friends/:userId',
                builder: (_, state) => FriendProfileScreen(
                  userId: state.pathParameters['userId']!,
                  nickname: state.extra as String?,
                ),
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
                builder: (_, state) => FinisseurStickScreen(
                  sessionId: state.pathParameters['id']!,
                ),
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
                builder: (_, state) => MatchAwaitOthersScreen(
                  matchId: state.pathParameters['id']!,
                ),
              ),
              GoRoute(
                path: '${MatchRoutes.finished}/:id',
                builder: (_, state) =>
                    MatchFinishedScreen(matchId: state.pathParameters['id']!),
              ),
            ],
          ),
          // Branch 1 — Home (mittiges Tab) + alle Top-Level-Aktionen, die
          // sonst kein eigenes Tab haben (Settings, Inbox, Friends/Groups,
          // Teams, Match-Flow, Training-Sessions, Profil + Profile-Edit).
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                builder: (_, _) => const HomeScreen(),
              ),
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
              ),
              GoRoute(
                path: AuthRoutes.inbox,
                builder: (_, _) => const InboxScreen(),
              ),
              GoRoute(
                path: AuthRoutes.editProfile,
                builder: (_, _) => const EditProfileScreen(),
              ),
              GoRoute(
                // Archiv der Nachrichten (über den Drawer erreichbar).
                path: '/inbox/archive',
                builder: (_, _) => const ArchiveScreen(),
              ),
              GoRoute(
                // Meine Vereine (P5): Liste, Gründen (Code-gated) und Detail.
                path: '/clubs',
                builder: (_, _) => const ClubsScreen(),
              ),
              GoRoute(
                path: '/clubs/create',
                builder: (_, _) => const ClubCreateScreen(),
              ),
              GoRoute(
                path: '/clubs/:id',
                builder: (_, state) =>
                    ClubDetailScreen(clubId: ClubId(state.pathParameters['id']!)),
              ),
              GoRoute(
                path: '/clubs/:id/add',
                builder: (_, state) => ClubAddMemberScreen(
                  clubId: ClubId(state.pathParameters['id']!),
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
              GoRoute(
                // Search-based add of a member (admin) or guest. Role via extra.
                path: '/teams/:id/add',
                builder: (_, state) => TeamAddPlayerScreen(
                  teamId: TeamId(state.pathParameters['id']!),
                  role: state.extra is TeamAddRole
                      ? state.extra! as TeamAddRole
                      : TeamAddRole.member,
                ),
              ),
              GoRoute(
                path: '/teams/:id/edit',
                builder: (_, state) => TeamEditScreen(
                  teamId: TeamId(state.pathParameters['id']!),
                ),
              ),
              // Profil ist kein eigenes Tab mehr (BottomNav-Redesign): die
              // Screens leben im Home-Branch und werden ueber den AppBar-
              // Avatar (`PlayerHubSheet` → `/profile`) bzw. die Account-
              // Section (`/profile/achievements`) erreicht.
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
              GoRoute(
                path: '/profile/achievements',
                builder: (_, _) => const AchievementsScreen(),
              ),
              GoRoute(
                // Eigene online gespeicherte Trainings ansehen + löschen (P2).
                path: '/profile/training-sessions',
                builder: (_, _) => const MyTrainingSessionsScreen(),
              ),
            ],
          ),
          // Branch 2 — Tournaments. Der /tournament-Hub ist der Tab-Root;
          // Discovery-Liste, eigene Anmeldungen, Setup-Wizard und der
          // Statistik-Platzhalter leben im selben Branch, damit ein Hub-Tap
          // (context.push) auf dem Tournaments-Stack bleibt und der
          // BottomNav-Index nicht wegspringt.
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: TournamentRoutes.hub,
                builder: (_, _) => const TournamentHubScreen(),
              ),
              GoRoute(
                path: TournamentRoutes.list,
                builder: (_, _) => const TournamentListScreen(),
              ),
              GoRoute(
                path: TournamentRoutes.registrations,
                builder: (_, _) => const TournamentRegistrationsScreen(),
              ),
              GoRoute(
                path: TournamentRoutes.stats,
                builder: (_, _) => const TournamentStatsScreen(),
              ),
              GoRoute(
                path: TournamentRoutes.pastTournaments,
                builder: (_, _) => const TournamentPastScreen(),
              ),
              GoRoute(
                path: TournamentRoutes.mercenaryMarket,
                builder: (_, _) => const TournamentMercenaryScreen(),
              ),
              GoRoute(
                path: TournamentRoutes.ranking,
                builder: (_, _) => const TournamentRankingScreen(),
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
                path: '/tournament/:id/edit',
                builder: (_, state) => TournamentEditScreen(
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
                // Team-registration hand-off target from
                // TournamentRegistrationScreen for team tournaments. Was
                // missing → pushing it hit a routeless blank screen (no
                // errorBuilder existed), so team registration dead-ended.
                path: '/tournament/:id/register/team',
                builder: (_, state) => RegisterTeamScreen(
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
                // CF6 (K19): organizer-only manual-seeding editor reached on
                // the Vorrunde->KO transition when seeding_mode == manual.
                path: '/tournament/:id/seeding',
                builder: (_, state) => TournamentSeedingScreen(
                  tournamentId: state.pathParameters['id']!,
                ),
              ),
              GoRoute(
                path: '/tournament/:id/dashboard',
                builder: (_, state) => TournamentLiveDashboardScreen(
                  tournamentId: state.pathParameters['id']!,
                ),
              ),
              GoRoute(
                // P6 shoot-out report/confirm — entry point is the shoot-out
                // inbox message; the tie group is addressed by its zero-based
                // start rank.
                path: '/tournament/:id/shootout/:startRank',
                builder: (_, state) => TournamentShootoutScreen(
                  tournamentId: state.pathParameters['id']!,
                  startRank:
                      int.tryParse(state.pathParameters['startRank'] ?? '') ?? 0,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Root-Scaffold fuer die authenticated Tab-Shell.
///
/// Haelt nur eine [StatefulNavigationShell] als Body plus die globale
/// [KubbBottomNav]. Tab-Wechsel laufen ueber `navigationShell.goBranch`;
/// ein Tap auf den aktiven Tab fuehrt zurueck auf den Branch-Root
/// (`initialLocation: true`), analog zum Material-3-Standard.
class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: KubbBottomNav(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

class _AuthRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}
