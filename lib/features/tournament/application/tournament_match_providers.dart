import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Fallback polling cadence used ONLY while the realtime channel is
/// unhealthy (≥60 s errored or kill-switch off). 30 s per ADR-0029 §(c)
/// FC-6; the per-tournament match CDC feed is the live source.
const Duration _matchFallbackPollInterval = Duration(seconds: 30);

/// All matches for one tournament, fetched via the
/// `tournament_list_matches` RPC. Polled at the screen level via
/// [tournamentMatchListPollingProvider] so the bracket / round list
/// stays in sync with consensus-round bumps and finalisation.
//
// ignore: specify_nonobvious_property_types
final tournamentMatchListProvider =
    FutureProvider.family<List<TournamentMatchRef>, TournamentId>(
        (ref, id) async {
  return ref.read(tournamentRemoteProvider).listMatchesForTournament(id);
});

/// Single-match detail. Null when the caller is not authorised or the
/// id does not exist server-side.
//
// ignore: specify_nonobvious_property_types
final tournamentMatchDetailProvider =
    FutureProvider.family<TournamentMatchRef?, TournamentMatchId>(
        (ref, id) async {
  return ref.read(tournamentRemoteProvider).getMatch(id);
});

/// Side-effect provider keeping the detail provider fresh. The
/// per-tournament match CDC feed is the live source (ADR-0029 §(c) FC-6);
/// polling is ONLY a failure-mode, gated on [realtimeFallbackProvider] for
/// the match's tournament. A single self-rearming 30 s timer runs while the
/// channel is unhealthy and is cancelled on recovery — no unconditional
/// `Timer.periodic`. The terminal-state stop (`finalized` / `overridden` /
/// `voided` → no invalidate) is preserved and checked before each refresh.
//
// ignore: specify_nonobvious_property_types
final tournamentMatchPollingProvider =
    Provider.autoDispose.family<void, TournamentMatchId>((ref, id) {
  // The fallback gate is keyed on the match's tournament — derive it from
  // the loaded detail. Until the detail resolves there is no tournament to
  // gate on, so no fallback timer is armed.
  final tournamentId = ref
      .watch(tournamentMatchDetailProvider(id))
      .maybeWhen<TournamentId?>(
        data: (m) => m?.tournamentId,
        orElse: () => null,
      );
  if (tournamentId == null) return;

  Timer? fallbackTimer;
  void armFallback() {
    fallbackTimer = Timer(_matchFallbackPollInterval, () {
      fallbackTimer = null;
      final status = ref.read(tournamentMatchDetailProvider(id)).maybeWhen<
          TournamentMatchStatus?>(
        data: (m) => m?.status,
        orElse: () => null,
      );
      // Terminal-state stop: a finalised/overridden/voided match never
      // changes again, so skip the invalidate AND stop re-arming — the
      // fallback timer self-terminates instead of looping a perpetual
      // no-op while the channel stays errored.
      if (status == TournamentMatchStatus.finalized ||
          status == TournamentMatchStatus.overridden ||
          status == TournamentMatchStatus.voided) {
        return;
      }
      ref.invalidate(tournamentMatchDetailProvider(id));
      armFallback();
    });
  }

  final fallbackSub = ref.listen<AsyncValue<bool>>(
    realtimeFallbackProvider(tournamentId),
    (_, next) {
      final polling = next.maybeWhen(data: (v) => v, orElse: () => false);
      if (polling) {
        if (fallbackTimer == null) armFallback();
      } else {
        fallbackTimer?.cancel();
        fallbackTimer = null;
      }
    },
    fireImmediately: true,
  );

  ref.onDispose(() {
    fallbackTimer?.cancel();
    fallbackSub.close();
  });
});

/// List-level polling for the match list screen. The per-tournament match
/// CDC feed is the live source (ADR-0029 §(c) FC-6); polling is ONLY a
/// failure-mode, gated on [realtimeFallbackProvider]. A single self-rearming
/// 30 s timer runs while the channel is unhealthy and is cancelled on
/// recovery — no unconditional `Timer.periodic`.
//
// ignore: specify_nonobvious_property_types
final tournamentMatchListPollingProvider =
    Provider.autoDispose.family<void, TournamentId>((ref, id) {
  Timer? fallbackTimer;
  void armFallback() {
    fallbackTimer = Timer(_matchFallbackPollInterval, () {
      ref.invalidate(tournamentMatchListProvider(id));
      armFallback();
    });
  }

  final fallbackSub = ref.listen<AsyncValue<bool>>(
    realtimeFallbackProvider(id),
    (_, next) {
      final polling = next.maybeWhen(data: (v) => v, orElse: () => false);
      if (polling) {
        if (fallbackTimer == null) armFallback();
      } else {
        fallbackTimer?.cancel();
        fallbackTimer = null;
      }
    },
    fireImmediately: true,
  );

  ref.onDispose(() {
    fallbackTimer?.cancel();
    fallbackSub.close();
  });
});

/// Participants/check-in fallback poller (Spec §3.1, acceptance 5.6, W1-T12).
///
/// The `tournament_participants` CDC drives check-in freshness live (ADR-0031
/// D3), but it had no fallback poller — if the channel falls over for ≥60 s,
/// check-in freshness drops to zero. This poller closes that gap exactly like
/// [tournamentMatchListPollingProvider]: gated on the SAME
/// [realtimeFallbackProvider] gate, it invalidates [tournamentDetailProvider]
/// (which carries the participant + check-in snapshot) on the 30 s fallback
/// cadence. A single self-rearming timer runs only while the channel is
/// unhealthy and is cancelled on recovery — no unconditional `Timer.periodic`,
/// no held background socket (ADR-0029).
//
// ignore: specify_nonobvious_property_types
final tournamentParticipantsPollingProvider =
    Provider.autoDispose.family<void, TournamentId>((ref, id) {
  Timer? fallbackTimer;
  void armFallback() {
    fallbackTimer = Timer(_matchFallbackPollInterval, () {
      ref.invalidate(tournamentDetailProvider(id));
      armFallback();
    });
  }

  final fallbackSub = ref.listen<AsyncValue<bool>>(
    realtimeFallbackProvider(id),
    (_, next) {
      final polling = next.maybeWhen(data: (v) => v, orElse: () => false);
      if (polling) {
        if (fallbackTimer == null) armFallback();
      } else {
        fallbackTimer?.cancel();
        fallbackTimer = null;
      }
    },
    fireImmediately: true,
  );

  ref.onDispose(() {
    fallbackTimer?.cancel();
    fallbackSub.close();
  });
});

/// Client-side standings computation for M1. Uses
/// [computeStandings] from `kubb_domain` over finalised matches only.
/// The server gains a dedicated RPC in M2 — until then we fold the
/// per-match final scores into a single round-result list.
//
// ignore: specify_nonobvious_property_types
final tournamentStandingsProvider =
    FutureProvider.family<List<ParticipantStats>, TournamentId>(
        (ref, id) async {
  final remote = ref.read(tournamentRemoteProvider);
  final matches = await remote.listMatchesForTournament(id);
  // CF2 / ChangeSpec K04: the standings point source follows the
  // tournament's scoring mode (tournaments.scoring). Read it from the
  // detail header; fall back to EKC when the detail is unavailable
  // (no read access / not yet loaded) so behaviour is unchanged for
  // the historical default.
  final detail = await remote.getTournamentDetail(id);
  final scoring = detail?.tournament.scoring ?? TournamentScoring.ekc;
  final format = detail?.tournament.format ?? TournamentFormat.roundRobin;
  final tiebreakerOrder =
      detail?.tournament.tiebreakerOrder ?? const <String>[];
  // M1-T07: a Schoch bye is a full win worth 16 (schoch-swiss spec §4.2);
  // every other format keeps its zero bye. When the detail is unavailable we
  // fall back to round-robin's zero so behaviour is unchanged.
  final byeScore = schochByeScoreFor(format);
  final participantIds = <String>{
    for (final m in matches) ...[
      if (m.participantA != null) m.participantA!.value,
      if (m.participantB != null) m.participantB!.value,
    ],
  }.toList(growable: false);

  // FF2 / Finding B: build the standings input from each match. In
  // classic mode tournament_list_matches now projects the real per-side
  // set wins (sets_won_a/_b, same source as tournament_pool_standings), so
  // the synthesis reconstructs real set wins instead of a single match
  // win — client and server classic standings now agree for best-of-3.
  // The EKC path is unchanged (single-set synthesis from finalScoreA/B).
  final results = <TournamentMatchResult>[
    for (final m in matches.where(_isStandingsCounted))
      _resultFromMatch(m, scoring),
  ];

  return computeStandings(
    participantIds: participantIds,
    results: results,
    scoring: scoring,
    byeScoreForUnopposedParticipant: byeScore,
    // Spec §5.3: read the tiebreak chain from the configured order, mapped
    // to the format's preliminary stage type — schoch layers Buchholz,
    // group/round-robin strips it (Buchholz never separates same-pool
    // opponents), instead of the old hard-wired chain.
    tiebreaker: standingsChainFor(
      preliminaryStageTypeFor(format),
      tiebreakerOrder,
    ),
  );
});

/// The preliminary (Vorrunde) stage type a [TournamentFormat] ranks under,
/// used to pick the standings tiebreak chain (spec §5.3, vorrunde-ranking).
/// The KO-only [TournamentFormat.singleElimination] has no league phase, so
/// it falls back to the single-elim chain.
StageNodeType preliminaryStageTypeFor(TournamentFormat format) {
  switch (format) {
    case TournamentFormat.roundRobin:
      return StageNodeType.roundRobin;
    case TournamentFormat.roundRobinThenKo:
      return StageNodeType.groupPhase;
    case TournamentFormat.schoch:
    case TournamentFormat.schochThenKo:
      return StageNodeType.schoch;
    case TournamentFormat.singleElimination:
      return StageNodeType.singleElim;
  }
}

bool _isStandingsCounted(TournamentMatchRef m) {
  return m.status == TournamentMatchStatus.finalized ||
      m.status == TournamentMatchStatus.overridden;
}

TournamentMatchResult _resultFromMatch(
  TournamentMatchRef m,
  TournamentScoring scoring,
) {
  return tournamentMatchResultFromFinalScore(
    participantA: m.participantA!.value,
    participantB: m.participantB?.value,
    finalScoreA: m.finalScoreA ?? 0,
    finalScoreB: m.finalScoreB ?? 0,
    scoring: scoring,
    setsWonA: m.setsWonA,
    setsWonB: m.setsWonB,
  );
}
