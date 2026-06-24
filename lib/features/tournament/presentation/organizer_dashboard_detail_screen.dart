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
import 'package:kubb_app/features/tournament/presentation/tournament_detail_screen.dart'
    show ParticipantCheckinToggle;
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
          roundNumber: activeRow?.roundNumber,
          remainingSeconds:
              activeRow == null ? null : _remainingSeconds(activeRow),
          onStart: () => actions.startTournament(tournamentId).ignore(),
          onPause: () => actions.pause(tournamentId).ignore(),
          onResume: () => actions.resume(tournamentId).ignore(),
          onSkipForward: () => actions.skipForward(tournamentId).ignore(),
          onSkipBack: () => actions.skipBack(tournamentId).ignore(),
          onExtend: (s) => actions.extendRound(tournamentId, s).ignore(),
          onShorten: (s) => actions.shortenRound(tournamentId, s).ignore(),
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
        // Schoch/Swiss next-round CTA (ADR-0039 §3 / ADR-0036): surfaces once
        // the active stage's latest round is complete and it is not the last
        // round. The pairing is computed client-side and submitted stage-scoped.
        _SwissPairAction(
          tournamentId: tournamentId,
          detail: detail,
          matches: matches,
        ),
        // Per-tournament on-site check-in (spec §9.2 / §10): the check-in that
        // lived inline on the detail screen now also lands here in the cockpit
        // (the detail-screen entkernung itself is 4d). Only shown while the
        // tournament is inside the check-in window; the server re-checks the
        // same gate + status, so this governs visibility only.
        if (_checkinWindowOpen(detail.tournament.status)) ...[
          const SizedBox(height: KubbTokens.space5),
          _CheckinSection(tournamentId: tournamentId, detail: detail),
        ],
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

  /// Remaining seconds of the active round per the Restzeit-Formel
  /// (round_schedule.dart §Modell). A static snapshot at build time — the
  /// schedule CDC re-renders this on every server-side change (pause / adjust /
  /// skip), so no local ticker is needed in the control bar.
  int _remainingSeconds(TournamentRoundScheduleRef row) {
    final now = DateTime.now().toUtc();
    final elapsed = now.difference(row.startsAt).inSeconds -
        row.pausedAccumSeconds -
        (row.pausedAt != null ? now.difference(row.pausedAt!).inSeconds : 0);
    return row.matchSeconds - elapsed;
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

  /// On-site check-in window (OE-D1): only registration_open /
  /// registration_closed / live accept a check-in. Mirrors the detail-screen
  /// gate so the cockpit section appears in exactly the same states.
  bool _checkinWindowOpen(TournamentStatus status) =>
      status == TournamentStatus.registrationOpen ||
      status == TournamentStatus.registrationClosed ||
      status == TournamentStatus.live;

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

/// Per-tournament on-site check-in section for the cockpit detail (spec §9.2 /
/// §10). Lists the confirmed pool with a [ParticipantCheckinToggle] per row,
/// reusing the existing `tournament_checkin_participant` / `tournament_undo_
/// checkin` RPCs via [TournamentActions]. Invalidating the detail provider
/// after each toggle re-reads the presence (the participant CDC drives the
/// same refresh).
class _CheckinSection extends ConsumerWidget {
  const _CheckinSection({required this.tournamentId, required this.detail});

  final TournamentId tournamentId;
  final TournamentDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final actions = ref.read(tournamentActionsProvider);
    final confirmed = detail.participants
        .where((p) =>
            p.registrationStatus == TournamentParticipantStatus.approved)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.organizerCheckinSectionTitle,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        if (confirmed.isEmpty)
          Text(
            l.tournamentDetailParticipantsEmpty,
            style: TextStyle(fontSize: 13, color: tokens.fgMuted),
          )
        else ...[
          Text(
            l.tournamentDetailCheckedInCount(
              confirmed.where((p) => p.isCheckedIn).length,
              confirmed.length,
            ),
            style: TextStyle(fontSize: 12, color: tokens.fgMuted),
          ),
          const SizedBox(height: KubbTokens.space1),
          for (final p in confirmed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: KubbTokens.space1),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p.displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: tokens.fg,
                      ),
                    ),
                  ),
                  ParticipantCheckinToggle(
                    isCheckedIn: p.isCheckedIn,
                    onCheckin: () => actions
                        .checkin(
                          TournamentParticipantId(p.participantId),
                          tournamentId: tournamentId,
                        )
                        .ignore(),
                    onUndoCheckin: () => actions
                        .undoCheckin(
                          TournamentParticipantId(p.participantId),
                          tournamentId: tournamentId,
                        )
                        .ignore(),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
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
              // Pitch badge (W4-T04 / cockpit-spec §4): the assigned pitch from
              // the W0 projection. Hidden when the match has no pitch stamped.
              if (match.pitchNumber != null) ...[
                _PitchBadge(pitch: match.pitchNumber!),
                const SizedBox(width: KubbTokens.space2),
              ],
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
            // W4-T08 / cockpit-spec §5: direct score entry on every open
            // (non-disputed) match. Opens the override editor in direct mode.
            _MatchActionButton(
              icon: Icons.edit_outlined,
              label: l.organizerMatchActionDirectScore,
              color: tokens.accent,
              onTap: () => context.push(
                TournamentRoutes.directScore(
                  tournamentId.value,
                  match.matchId.value,
                ),
              ),
            ),
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

/// Small pitch-number badge on a [_MatchRow] (W4-T04 / cockpit-spec §4). Shows
/// the assigned pitch from the W0 projection so the organizer can see at a
/// glance which field a match runs on. Only rendered when a pitch is assigned.
class _PitchBadge extends StatelessWidget {
  const _PitchBadge({required this.pitch});

  final int pitch;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusSm),
        border: Border.all(color: tokens.line),
      ),
      child: Text(
        AppLocalizations.of(context).organizerMatchPitchBadge(pitch),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: tokens.fgMuted,
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
///   * otherwise (auto seeding) -> prime the shared seeding controller with the
///     auto-seeded standings order + `KoPhaseConfig` (exactly as
///     `tournament_seeding_screen.dart` does in its post-frame `seed(...)`
///     callback) and then trigger the existing `startKoPhase`, which calls the
///     `tournament_start_ko_phase` RPC. No new server/RPC logic is added here.
///
/// The priming is REQUIRED: a freshly built `tournamentSeedingControllerProvider`
/// returns `SeedingState.empty()` with `config == null`, and `startKoPhase()`
/// no-ops (errors out, swallowed) until `seed(...)` has populated the config.
/// The dashboard is a second entry-point into that controller, so it must run
/// the same priming the seeding screen does before firing the RPC.
///
/// Swiss/Schoch next-round pairing is a SEPARATE CTA, [_SwissPairAction] (this
/// handover is KO-only). The client computes that pairing in Dart and submits
/// it stage-scoped — see [TournamentActions.pairRound] and ADR-0036/ADR-0039.
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

    final manual = _seedingMode(detail) == SeedingMode.manual;
    // Auto seeding: derive the seed order from the live standings (same source
    // the seeding screen uses) so the controller can be primed before the RPC.
    final autoOrder = manual
        ? const <TournamentParticipantId>[]
        : ref.watch(tournamentStandingsProvider(tournamentId)).maybeWhen(
              data: (standings) => <TournamentParticipantId>[
                for (final s in standings)
                  TournamentParticipantId(s.participantId),
              ],
              orElse: () => const <TournamentParticipantId>[],
            );

    return SizedBox(
      height: KubbTokens.touchComfortable,
      child: FilledButton.icon(
        icon: const Icon(Icons.sports_kabaddi_outlined, size: 18),
        label: Text(l.organizerKoTransitionAction),
        onPressed: () {
          if (manual) {
            // Manual seeding: the organizer commits a seed list first via the
            // existing seeding editor (server re-enforces seeding_required).
            unawaited(
              context.push(TournamentRoutes.seeding(tournamentId.value)),
            );
          } else {
            // Auto seeding: prime the shared seeding controller with the
            // standings-derived order + config (mirroring the seeding screen's
            // post-frame seed(...) call), THEN reuse the existing startKoPhase
            // mechanic. Without this priming startKoPhase() hits its
            // config==null guard and silently no-ops (no extra step, no RPC).
            final notifier = ref
                .read(tournamentSeedingControllerProvider(tournamentId).notifier)
              ..seed(
                auto: autoOrder,
                config: _autoKoConfig(autoOrder.length),
              );
            notifier.startKoPhase().ignore();
          }
        },
      ),
    );
  }
}

/// Schoch/Swiss next-round CTA (ADR-0039 §3 / ADR-0036, M4 #4). Surfaces only
/// while a Schoch stage is mid-flight: the tournament is `live`, the format is
/// schoch-family, the stage's latest round is fully terminal
/// (swiss_round_complete) and it is not yet the last configured round (`r < R`).
/// On tap it fires [TournamentActions.pairRound], which RECHNET the pairing in
/// Dart and submits it stage-scoped — the server only validates. Hidden when no
/// stage-scoped Schoch round is ready to pair, so it never competes with the
/// KO-handover CTA above.
class _SwissPairAction extends ConsumerWidget {
  const _SwissPairAction({
    required this.tournamentId,
    required this.detail,
    required this.matches,
  });

  final TournamentId tournamentId;
  final TournamentDetail detail;
  final List<TournamentMatchRef> matches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;

    final stage = _pairableStage();
    if (stage == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: KubbTokens.space3),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: KubbTokens.touchMin,
          child: FilledButton.icon(
            onPressed: () => ref
                .read(tournamentActionsProvider)
                .pairRound(tournamentId, stage)
                .ignore(),
            icon: const Icon(Icons.casino_outlined, size: 18),
            label: Text(l.organizerPairNextRound),
            style: FilledButton.styleFrom(
              backgroundColor: tokens.accent,
              foregroundColor: tokens.onAccent,
            ),
          ),
        ),
      ),
    );
  }

  /// The stage node whose next Schoch round can be paired now, or null when
  /// none qualifies. A stage qualifies when the tournament is live + a
  /// schoch-family format, the stage has matches, its highest round is fully
  /// terminal, and that round is below the configured count `R`.
  String? _pairableStage() {
    if (detail.tournament.status != TournamentStatus.live) return null;
    final format = detail.tournament.format;
    if (format != TournamentFormat.schoch &&
        format != TournamentFormat.schochThenKo) {
      return null;
    }
    final rounds = _schochRounds();

    final byStage = <String, List<TournamentMatchRef>>{};
    for (final m in matches) {
      final node = m.stageNodeId;
      if (node == null) continue;
      (byStage[node] ??= <TournamentMatchRef>[]).add(m);
    }

    for (final entry in byStage.entries) {
      final latest = entry.value
          .map((m) => m.roundNumber)
          .fold<int>(0, (a, b) => a > b ? a : b);
      if (latest >= rounds) continue;
      final latestComplete = entry.value
          .where((m) => m.roundNumber == latest)
          .every((m) =>
              m.status == TournamentMatchStatus.finalized ||
              m.status == TournamentMatchStatus.overridden ||
              m.status == TournamentMatchStatus.voided);
      if (latestComplete) return entry.key;
    }
    return null;
  }

  /// Configured Schoch round count `R`, read from
  /// `setup.pool_phase_config.schoch_rounds`; falls back to the domain default.
  int _schochRounds() {
    final pool = detail.tournament.setup['pool_phase_config'];
    if (pool is Map) {
      final raw = pool['schoch_rounds'];
      if (raw is int && raw >= 1) return raw;
    }
    return defaultSchochRounds;
  }
}

/// Default "all qualified -> KO" config for the auto-seeding handover, matching
/// `tournament_seeding_screen.dart`'s `_config`. The server re-validates and is
/// the authority; this only satisfies the controller's `config != null`
/// precondition for the existing `startKoPhase` mechanic.
KoPhaseConfig _autoKoConfig(int participantCount) {
  final n = participantCount < 2 ? 2 : participantCount;
  return KoPhaseConfig(qualifierCount: n, participantCount: n);
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
