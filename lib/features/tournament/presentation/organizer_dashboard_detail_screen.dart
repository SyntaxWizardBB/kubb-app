import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_seeding_controller.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/schedule_control_bar.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_forfeit_sheet.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Per-tournament organizer dashboard DETAIL (ADR-0031 Phase B, Block B4).
///
/// Shows the round/match list of ONE tournament plus a [ScheduleControlBar]
/// (Start / Pause / Resume / Skip-forward / Skip-back) wired to
/// `TournamentActions.pause` / `.resume` / `.skipForward` / `.skipBack` (and
/// `.startTournament` for the initial start). The irreversible skip-forward is
/// guarded by the hold affordance inside the control bar.
///
/// The schedule status driving the control bar is read from the Phase-A
/// CDC-fold [tournamentRoundScheduleProvider] (`watchRoundSchedule`) — the
/// schedule is PUSHED, never polled (ADR-0029). The round/match list comes
/// from [tournamentMatchListProvider]; the live `tournament_matches` CDC
/// (watched here) keeps it fresh.
///
/// In-screen gate (OE-B5): when [canAdministerTournamentProvider] resolves to
/// false the action UI is replaced by a [KubbEmptyState]. The server stays the
/// security boundary — this is a pure UX layer, no router redirect.
class OrganizerDashboardDetailScreen extends ConsumerWidget {
  const OrganizerDashboardDetailScreen({required this.tournamentId, super.key});

  final TournamentId tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    // Keep the match list fresh via the per-tournament matches CDC (no poll).
    ref.watch(tournamentMatchListRealtimeProvider(tournamentId));
    final detailAsync = ref.watch(tournamentDetailProvider(tournamentId));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.organizerDashboardDetailEyebrow,
        title: detailAsync.maybeWhen(
          data: (d) =>
              d?.tournament.displayName ?? l.organizerDashboardTitle,
          orElse: () => l.organizerDashboardTitle,
        ),
      ),
      body: detailAsync.when(
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
        data: (detail) {
          if (detail == null) {
            return KubbEmptyState(
              title: l.organizerDashboardGateTitle,
              body: l.organizerDashboardGateBody,
            );
          }
          // In-screen gate (OE-B5 / K4): Creator OR club
          // {owner,admin,organizer,referee}. Server stays the boundary.
          final canAdminister = ref.watch(
            canAdministerTournamentProvider((
              clubId: detail.tournament.clubId,
              createdBy: detail.tournament.createdByUserId,
            )),
          );
          if (!canAdminister) {
            return KubbEmptyState(
              title: l.organizerDashboardGateTitle,
              body: l.organizerDashboardGateBody,
            );
          }
          return _Body(tournamentId: tournamentId, detail: detail);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.tournamentId, required this.detail});

  final TournamentId tournamentId;
  final TournamentDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final actions = ref.read(tournamentActionsProvider);

    // Active schedule row (Phase-A CDC fold, pushed not polled). The detail
    // tracks the active round via the lowest non-completed schedule row.
    final scheduleMap = ref
        .watch(tournamentRoundScheduleProvider(tournamentId))
        .maybeWhen<Map<({int roundNumber, String? stageNodeId}),
            TournamentRoundScheduleRef>>(
          data: (rows) => rows,
          orElse: () => const {},
        );
    final activeRow = _activeScheduleRow(scheduleMap.values);
    final paused = activeRow?.pausedAt != null;

    final matches = ref
        .watch(tournamentMatchListProvider(tournamentId))
        .maybeWhen<List<TournamentMatchRef>>(
          data: (m) => m,
          orElse: () => detail.matches,
        );
    final byRound = _groupByRound(matches);

    // B3 escalation counts derived from the followed match list. `disputed`
    // matches feed the override entry-point; `scheduled`/`awaitingResults`
    // (open / no-show-able) feed the forfeit shortcut. The badges only
    // surface when their count > 0 so the section stays quiet when nothing
    // needs an organizer intervention.
    final disputedCount = matches
        .where((m) => m.status == TournamentMatchStatus.disputed)
        .length;
    final openCount = matches
        .where((m) =>
            m.status == TournamentMatchStatus.scheduled ||
            m.status == TournamentMatchStatus.awaitingResults)
        .length;

    return ListView(
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        Text(
          l.organizerControlSectionTitle,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        ScheduleControlBar(
          scheduleStatus: activeRow?.status,
          paused: paused,
          onStart: () => actions.startTournament(tournamentId).ignore(),
          onPause: () => actions.pause(tournamentId).ignore(),
          onResume: () => actions.resume(tournamentId).ignore(),
          onSkipForward: () => actions.skipForward(tournamentId).ignore(),
          onSkipBack: () => actions.skipBack(tournamentId).ignore(),
        ),
        const SizedBox(height: KubbTokens.space5),
        Text(
          l.organizerEscalationSectionTitle,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        _EscalationBadges(
          disputedCount: disputedCount,
          openCount: openCount,
        ),
        const SizedBox(height: KubbTokens.space3),
        // KO transition CTA: only on the Vorrunde->KO handover, mirroring the
        // CF6/K19 branch in tournament_detail_screen.dart. Reuses the existing
        // seeding route (manual seeding without a bracket) or the existing
        // startKoPhase mechanic (auto seeding) — no new server/RPC logic.
        _KoTransitionAction(tournamentId: tournamentId, detail: detail),
        const SizedBox(height: KubbTokens.space5),
        Text(
          l.organizerDashboardRoundsTitle,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        if (byRound.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KubbTokens.space5),
            child: Text(
              l.organizerDashboardNoMatches,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: tokens.fgMuted),
            ),
          )
        else
          for (final entry in byRound.entries) ...[
            _RoundHeader(round: entry.key),
            const SizedBox(height: KubbTokens.space2),
            for (final match in entry.value) ...[
              _MatchRow(tournamentId: tournamentId, match: match),
              const SizedBox(height: KubbTokens.space2),
            ],
            const SizedBox(height: KubbTokens.space3),
          ],
      ],
    );
  }

  /// The lowest-numbered non-completed schedule row — the round the runner is
  /// currently driving (matches the A4 detail-screen convention).
  TournamentRoundScheduleRef? _activeScheduleRow(
    Iterable<TournamentRoundScheduleRef> rows,
  ) {
    TournamentRoundScheduleRef? active;
    for (final row in rows) {
      if (row.status == RoundStatus.completed) continue;
      if (active == null || row.roundNumber < active.roundNumber) {
        active = row;
      }
    }
    return active;
  }

  Map<int, List<TournamentMatchRef>> _groupByRound(
    List<TournamentMatchRef> matches,
  ) {
    final map = <int, List<TournamentMatchRef>>{};
    for (final m in matches) {
      (map[m.roundNumber] ??= <TournamentMatchRef>[]).add(m);
    }
    final sorted = map.keys.toList()..sort();
    return {
      for (final r in sorted)
        r: (map[r]!..sort((a, b) =>
            a.matchNumberInRound.compareTo(b.matchNumberInRound))),
    };
  }
}

class _RoundHeader extends StatelessWidget {
  const _RoundHeader({required this.round});

  final int round;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Text(
      l.organizerDashboardRoundLabel(round),
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: tokens.fg,
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.tournamentId, required this.match});

  final TournamentId tournamentId;
  final TournamentMatchRef match;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final disputed = match.status == TournamentMatchStatus.disputed;
    // Open / no-show-able states the forfeit shortcut applies to (mirrors the
    // escalation-count derivation in [_Body]).
    final open = match.status == TournamentMatchStatus.scheduled ||
        match.status == TournamentMatchStatus.awaitingResults;
    final a = match.participantADisplayName ?? '—';
    final b = match.participantBDisplayName ?? '—';
    final scoreA = match.setsWonA ?? match.finalScoreA;
    final scoreB = match.setsWonB ?? match.finalScoreB;
    final score = (scoreA != null && scoreB != null) ? '$scoreA : $scoreB' : '—';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space3,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(
          color: disputed ? KubbTokens.miss : tokens.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$a  vs  $b',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
              ),
              const SizedBox(width: KubbTokens.space2),
              Text(
                score,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: disputed ? KubbTokens.miss : tokens.fgMuted,
                ),
              ),
            ],
          ),
          // B3 contextual intervention links — reuse existing entry-points
          // only. Disputed -> existing override route; open/no-show ->
          // existing TournamentForfeitSheet (declareForfeit). The CTA only
          // appears for the matching status, never both.
          if (disputed) ...[
            const SizedBox(height: KubbTokens.space2),
            _MatchActionButton(
              icon: Icons.gavel_outlined,
              label: l.organizerMatchActionOverride,
              color: KubbTokens.miss,
              // DOD-03: routes to the EXISTING organizer override screen.
              onTap: () => context.push(
                TournamentRoutes.override(
                  tournamentId.value,
                  match.matchId.value,
                ),
              ),
            ),
          ] else if (open) ...[
            const SizedBox(height: KubbTokens.space2),
            _MatchActionButton(
              icon: Icons.flag_outlined,
              label: l.organizerMatchActionForfeit,
              color: tokens.fgMuted,
              // DOD-04: opens the EXISTING forfeit sheet (no new dialog).
              onTap: () => TournamentForfeitSheet.show(
                context,
                matchId: match.matchId,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact, ≥48 dp per-match intervention button used by [_MatchRow] for the
/// override / forfeit shortcuts. Tokens-only styling (no hardcoded sizes).
class _MatchActionButton extends StatelessWidget {
  const _MatchActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: KubbTokens.touchMin,
        child: TextButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18, color: color),
          label: Text(label),
          style: TextButton.styleFrom(foregroundColor: color),
        ),
      ),
    );
  }
}

/// Escalation badges derived from the followed match list (DOD-07). Renders a
/// disputed and/or open indicator only when the respective count > 0; when
/// both are zero it shows a quiet "nothing to do" hint. The badges make the
/// associated intervention reachable (the per-match override/forfeit CTAs
/// live in [_MatchRow] below).
class _EscalationBadges extends StatelessWidget {
  const _EscalationBadges({
    required this.disputedCount,
    required this.openCount,
  });

  final int disputedCount;
  final int openCount;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    if (disputedCount == 0 && openCount == 0) {
      return Text(
        l.organizerEscalationNone,
        style: TextStyle(fontSize: 13, color: tokens.fgMuted),
      );
    }
    return Wrap(
      spacing: KubbTokens.space2,
      runSpacing: KubbTokens.space2,
      children: [
        if (disputedCount > 0)
          _Badge(
            icon: Icons.warning_amber_rounded,
            label: l.organizerEscalationDisputedBadge(disputedCount),
            color: KubbTokens.miss,
          ),
        if (openCount > 0)
          _Badge(
            icon: Icons.schedule_outlined,
            label: l.organizerEscalationOpenBadge(openCount),
            color: tokens.fgMuted,
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space2,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: KubbTokens.space2),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: tokens.fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// KO-transition CTA (DOD-05). Surfaces only on the Vorrunde->KO handover —
/// a `live` tournament whose KO bracket has not been materialised yet — and
/// reuses the EXISTING mechanics, mirroring the CF6/K19 branch in
/// `tournament_detail_screen.dart`:
///   * manual seeding without a bracket -> navigate to the existing seeding
///     route (the organizer must commit a seed list first);
///   * otherwise (auto seeding) -> trigger the existing `startKoPhase` on the
///     shared seeding controller (which calls the `tournament_start_ko_phase`
///     RPC). No new server/RPC logic is added here.
///
/// Swiss/pairRound is intentionally NOT linked here (DOD-06): there is no
/// existing client `pairRound` action/route in this branch (no
/// `TournamentActions.pairRound`, no port/repository RPC), and B3 forbids new
/// server/domain work, so inventing one is out of scope. The Swiss next-round
/// pairing stays driven by the existing result-trigger materialisation.
class _KoTransitionAction extends ConsumerWidget {
  const _KoTransitionAction({
    required this.tournamentId,
    required this.detail,
  });

  final TournamentId tournamentId;
  final TournamentDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // Only offer the handover while the tournament is live (the only status
    // from which the KO phase can be started).
    if (detail.tournament.status != TournamentStatus.live) {
      return const SizedBox.shrink();
    }
    // `tournamentBracketProvider` throws while still in the group phase
    // (no KO rows yet) — both error/loading fold to "no bracket yet".
    final hasBracket = ref.watch(tournamentBracketProvider(tournamentId)).maybeWhen(
          data: (b) => switch (b) {
            SingleEliminationBracket(:final rounds) => rounds.isNotEmpty,
            DoubleEliminationBracket(:final wbRounds) => wbRounds.isNotEmpty,
            ConsolationBracket(:final mainRounds, :final rounds) =>
              mainRounds.isNotEmpty || rounds.isNotEmpty,
          },
          orElse: () => false,
        );
    // Once a bracket exists the KO phase is already running — no handover CTA.
    if (hasBracket) return const SizedBox.shrink();

    return SizedBox(
      height: KubbTokens.touchComfortable,
      child: FilledButton.icon(
        icon: const Icon(Icons.sports_kabaddi_outlined, size: 18),
        label: Text(l.organizerKoTransitionAction),
        onPressed: () {
          if (_seedingMode(detail) == SeedingMode.manual) {
            // Manual seeding: the organizer commits a seed list first via the
            // existing seeding editor (server re-enforces seeding_required).
            unawaited(
              context.push(TournamentRoutes.seeding(tournamentId.value)),
            );
          } else {
            // Auto seeding: reuse the existing startKoPhase mechanic on the
            // shared seeding controller (no extra step, no new RPC).
            ref
                .read(tournamentSeedingControllerProvider(tournamentId).notifier)
                .startKoPhase()
                .ignore();
          }
        },
      ),
    );
  }
}

/// CF6 (K19) seeding-mode discriminator — read from `ko_config.seeding_mode`
/// on the projected setup map. Mirrors the helper in
/// `tournament_detail_screen.dart`; defaults to [SeedingMode.auto] so only an
/// explicit `manual` triggers the mandatory seeding step.
SeedingMode _seedingMode(TournamentDetail detail) {
  final ko = detail.tournament.setup['ko_config'];
  if (ko is Map && ko['seeding_mode'] == 'manual') {
    return SeedingMode.manual;
  }
  return SeedingMode.auto;
}
