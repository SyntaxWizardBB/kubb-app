import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/organizer_team/application/organizer_team_providers.dart';
import 'package:kubb_app/features/organizer_team/data/organizer_team_models.dart';
import 'package:kubb_app/features/organizer_team/presentation/organizer_team_routes.dart';
import 'package:kubb_app/features/tournament/application/server_clock_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/organizer_tournament_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Organizer dashboard OVERVIEW (ADR-0031 Phase B, Block B4) — the
/// multi-tournament veranstalter cockpit.
///
/// Lists one [OrganizerTournamentCard] per administrable tournament from the
/// single-RPC [administrableTournamentsProvider] (Creator + club
/// {owner,admin,organizer,referee}; no N+1). Each card surfaces phase/round,
/// the schedule status, a server-corrected remaining-time readout, the open-
/// and disputed-match badges, plus a quick action (Start while the tournament
/// has no running schedule, else Pause/Resume of the tournament-wide clock).
///
/// This screen is DELIBERATELY action-bearing — it is the opposite of the
/// read-only dashboard removed in `a46f962` (ADR-0031 §Kontext).
///
/// Refresh follows OE-B3: the overview has no single-column CDC scope, so it
/// must NOT poll (ADR-0029). The control actions invalidate the provider after
/// each write (see [TournamentActions]); the durable Inbox-CDC seam drives
/// background refreshes. The only timer in play is the 1-second UI render
/// ticker each card opens for its countdown (pure rendering, no fetch).
class OrganizerDashboardScreen extends ConsumerWidget {
  const OrganizerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final cardsAsync = ref.watch(administrableTournamentsProvider);
    final offset = ref.watch(serverClockOffsetProvider).maybeWhen<Duration>(
          data: (d) => d,
          orElse: () => Duration.zero,
        );
    // Pure 1-second UI render ticker for the per-card countdown (ADR-0029 /
    // DoD-14: rendering only, no server fetch). Injectable so widget tests can
    // drive (or suppress) the tick without leaking real timers.
    final ticker = ref.watch(dashboardCountdownTickerProvider);
    // P4-C (ADR-0032 §4): the caller's organizer teams for the
    // "Meine Veranstalterteams" section below the tournament cards.
    // Fail-closed: loading/error collapse to an empty list, which hides
    // the section entirely (no placeholder). One-shot Future read, no
    // polling (ADR-0029).
    final teams = ref.watch(organizerTeamListProvider).maybeWhen(
          data: (clubs) => clubs,
          orElse: () => const <OrganizerTeamWire>[],
        );

    // hub-cleanup-cockpit-tabs: split the cockpit into two top tabs so the
    // running-tournament management and the organizer-teams section never mix
    // in one scroll. Tab styling mirrors the live-screen TabBar (KubbTokens
    // colors). The TabBar sits under the app bar inside the body Column.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: tokens.bg,
        appBar: KubbAppBar(
          eyebrow: l.organizerDashboardEyebrow,
          title: l.organizerDashboardTitle,
        ),
        body: Column(
          children: [
            TabBar(
              labelColor: tokens.fg,
              unselectedLabelColor: tokens.fgMuted,
              indicatorColor: tokens.primary,
              tabs: [
                Tab(text: l.organizerDashboardTabTournaments),
                Tab(text: l.organizerDashboardTabTeams),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // Tab 1 "Turniere": the administrable-tournament cards plus
                  // their empty state — the existing cockpit, minus the teams
                  // section.
                  _TournamentsTab(
                    cardsAsync: cardsAsync,
                    offset: offset,
                    ticker: ticker,
                    onOpenDetail: (card) => context.push(
                      TournamentRoutes.dashboardDetail(card.tournamentId.value),
                    ),
                    onPrimaryAction: (card) => _runPrimaryAction(ref, card),
                  ),
                  // Tab 2 "Veranstalterteams": the teams list + the always-
                  // reachable "Veranstalterteam gründen" entry point.
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(KubbTokens.space4),
                    child: _OrganizerTeamsSection(
                      title: l.organizerDashboardTeamsTitle,
                      teams: teams,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The card's quick action: Start while the tournament has no running
  /// schedule yet, Pause while running, Resume while paused. All three route
  /// through [TournamentActions], which re-checks the server gate and
  /// invalidates the overview after the write.
  void _runPrimaryAction(WidgetRef ref, TournamentAdminCardRef card) {
    final actions = ref.read(tournamentActionsProvider);
    final id = card.tournamentId;
    if (card.pausedAt != null) {
      ref.read(_dashboardActionRunner)(actions.resume(id));
      return;
    }
    if (card.scheduleStatus == RoundStatus.running) {
      ref.read(_dashboardActionRunner)(actions.pause(id));
      return;
    }
    ref.read(_dashboardActionRunner)(actions.startTournament(id));
  }
}

/// hub-cleanup-cockpit-tabs: "Turniere" tab body — the administrable-
/// tournament cards (one [OrganizerTournamentCard] per card) plus the
/// loading/error/empty states. This is the former single-scroll cockpit
/// minus the teams section, which now lives in its own tab. All card
/// behavior (open detail, the start/pause/resume quick action, the countdown
/// ticker) is preserved — the callbacks are threaded through from the parent.
class _TournamentsTab extends StatelessWidget {
  const _TournamentsTab({
    required this.cardsAsync,
    required this.offset,
    required this.ticker,
    required this.onOpenDetail,
    required this.onPrimaryAction,
  });

  final AsyncValue<List<TournamentAdminCardRef>> cardsAsync;
  final Duration offset;
  final Stream<void>? ticker;
  final void Function(TournamentAdminCardRef) onOpenDetail;
  final void Function(TournamentAdminCardRef) onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return cardsAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text(
            l.organizerDashboardError,
            textAlign: TextAlign.center,
            style: const TextStyle(color: KubbTokens.miss),
          ),
        ),
      ),
      data: (cards) {
        if (cards.isEmpty) {
          // In-screen gate (OE-B5) for the overview: the source RPC
          // `tournament_list_administrable` is itself server-gated by
          // `tournament_caller_can_manage` (Creator OR club
          // {owner,admin,organizer,referee} — K4). An unauthorised caller
          // therefore receives an EMPTY list and sees this KubbEmptyState
          // instead of any action UI — same gate spirit as the detail
          // screen. The server stays the security boundary; this is UX only.
          // The founding CTA now lives in the Veranstalterteams tab, so the
          // empty Turniere tab is informational only.
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(KubbTokens.space4),
              child: KubbEmptyState(
                title: l.organizerDashboardEmptyTitle,
                body: l.organizerDashboardEmptyBody,
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(KubbTokens.space4),
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: KubbTokens.space3),
              OrganizerTournamentCard(
                card: cards[i],
                serverOffset: offset,
                ticker: ticker,
                onOpenDetail: () => onOpenDetail(cards[i]),
                onPrimaryAction: () => onPrimaryAction(cards[i]),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// P4-C (ADR-0032 §4): "Meine Veranstalterteams" — the caller's organizer
/// teams as a trailing section of the dashboard scroll. Visual pattern
/// mirrors the home screen's RecentSection (uppercase label + raised card
/// with divider rows); tokens exclusively via [KubbTokens].
///
/// fix/organizer-found-club-entry: this section now renders ALWAYS (even with
/// an empty [teams] list) and carries the only reachable entry point into the
/// founding/management flow (`OrganizerTeamRoutes.list` → "Verein gründen"
/// FAB + search/join). Rows are tappable into the team detail; a trailing
/// "gründen" button opens the clubs list; an empty list shows a muted hint.
class _OrganizerTeamsSection extends StatelessWidget {
  const _OrganizerTeamsSection({required this.title, required this.teams});

  final String title;
  final List<OrganizerTeamWire> teams;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final t = Theme.of(context).textTheme;
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: t.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.88,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Container(
          decoration: BoxDecoration(
            color: tokens.bgRaised,
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          ),
          padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space3),
          child: Column(
            children: [
              if (teams.isEmpty)
                // fix/organizer-found-club-entry: muted hint instead of a
                // bare card when the caller has no organizer team yet.
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: KubbTokens.space3,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.organizerDashboardNoTeams,
                          style: t.bodyMedium?.copyWith(color: tokens.fgMuted),
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (var i = 0; i < teams.length; i++)
                  InkWell(
                    onTap: () => context.push(
                      OrganizerTeamRoutes.detailFor(teams[i].id),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        border: i < teams.length - 1
                            ? Border(bottom: BorderSide(color: tokens.line))
                            : null,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: KubbTokens.space3,
                      ),
                      child: Row(
                        children: [
                          KubbIcon(
                            LucideIcons.shield,
                            size: 20,
                            color: tokens.fgMuted,
                          ),
                          const SizedBox(width: KubbTokens.space3),
                          Expanded(
                            child: Text(
                              teams[i].displayName,
                              style: t.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: tokens.fg,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          KubbIcon(
                            LucideIcons.chevronRight,
                            size: 18,
                            color: tokens.fgMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        // fix/organizer-found-club-entry: always-available entry point into
        // the founding/management flow — the clubs list owns the "Verein
        // gründen" FAB and the search/join (ADR-0032 §4).
        KubbButton(
          variant: KubbButtonVariant.secondary,
          onPressed: () => context.push(OrganizerTeamRoutes.list),
          child: Text(l.organizerDashboardFoundTeam),
        ),
      ],
    );
  }
}

/// Pure 1-second UI render ticker driving the overview cards' remaining-time
/// readout (ADR-0031 §Uhr). It performs NO server discovery (ADR-0029 /
/// DoD-14) — it only nudges the already-fetched countdown baseline down each
/// second. `null` means "render once, do not tick" (the card opens its own
/// `Stream.periodic` lazily). Widget tests override this with a controllable
/// stream so no real timer leaks across the test boundary.
final dashboardCountdownTickerProvider = Provider<Stream<void>?>((ref) => null);

/// Fire-and-forget runner for a control action `Future`. Keeps the
/// `unawaited`/error-swallow seam out of the widget tree so the card's
/// `onPressed` stays synchronous. Overridable in tests to assert the action
/// was dispatched without reaching the (async) server fake.
final _dashboardActionRunner = Provider<void Function(Future<void>)>((ref) {
  return (future) {
    // Errors surface via the provider invalidation/reload path; the dashboard
    // does not block the tap on the round-trip.
    future.ignore();
  };
});
