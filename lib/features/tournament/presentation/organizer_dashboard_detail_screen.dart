import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/schedule_control_bar.dart';
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
              _MatchRow(match: match),
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
  const _MatchRow({required this.match});

  final TournamentMatchRef match;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final disputed = match.status == TournamentMatchStatus.disputed;
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
      child: Row(
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
    );
  }
}
