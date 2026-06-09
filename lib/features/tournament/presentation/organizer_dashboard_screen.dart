import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/tournament/application/server_clock_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/organizer_tournament_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

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

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.organizerDashboardEyebrow,
        title: l.organizerDashboardTitle,
      ),
      body: cardsAsync.when(
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
            // screen, but the per-tournament `canAdministerTournamentProvider`
            // is not consulted here because the overview DTO
            // (`TournamentAdminCardRef`) carries no clubId/createdBy to feed
            // it. The server stays the security boundary; this is UX only.
            return KubbEmptyState(
              title: l.organizerDashboardEmptyTitle,
              body: l.organizerDashboardEmptyBody,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(KubbTokens.space4),
            itemCount: cards.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: KubbTokens.space3),
            itemBuilder: (context, index) {
              final card = cards[index];
              return OrganizerTournamentCard(
                card: card,
                serverOffset: offset,
                ticker: ticker,
                onOpenDetail: () => context.push(
                  TournamentRoutes.dashboardDetail(card.tournamentId.value),
                ),
                onPrimaryAction: () =>
                    _runPrimaryAction(ref, card),
              );
            },
          );
        },
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
