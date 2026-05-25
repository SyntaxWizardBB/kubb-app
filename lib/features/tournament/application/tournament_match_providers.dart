import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

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

/// Side-effect provider keeping the detail provider fresh. Stops
/// invalidating once the match enters a terminal lifecycle state
/// (`finalized` / `overridden` / `voided`). 5s cadence per M1 spec.
//
// ignore: specify_nonobvious_property_types
final tournamentMatchPollingProvider =
    Provider.autoDispose.family<void, TournamentMatchId>((ref, id) {
  final timer = Timer.periodic(const Duration(seconds: 5), (_) {
    final async = ref.read(tournamentMatchDetailProvider(id));
    final status = async.maybeWhen<TournamentMatchStatus?>(
      data: (m) => m?.status,
      orElse: () => null,
    );
    if (status == TournamentMatchStatus.finalized ||
        status == TournamentMatchStatus.overridden ||
        status == TournamentMatchStatus.voided) {
      return;
    }
    ref.invalidate(tournamentMatchDetailProvider(id));
  });
  ref.onDispose(timer.cancel);
});

/// List-level polling for the match list screen. Cheaper than detail
/// polling for every row; 5s cadence.
//
// ignore: specify_nonobvious_property_types
final tournamentMatchListPollingProvider =
    Provider.autoDispose.family<void, TournamentId>((ref, id) {
  final timer = Timer.periodic(const Duration(seconds: 5), (_) {
    ref.invalidate(tournamentMatchListProvider(id));
  });
  ref.onDispose(timer.cancel);
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
  final participantIds = <String>{
    for (final m in matches) ...[
      if (m.participantA != null) m.participantA!.value,
      if (m.participantB != null) m.participantB!.value,
    ],
  }.toList(growable: false);

  // Synthesise a single-set MatchEkcScore from `finalScoreA/B`. The
  // match cards themselves don't yet ship per-set detail on the
  // match-list RPC, so we approximate the inputs that
  // computeStandings needs: kubbs scored / conceded come from the
  // final score, the winner comes from whichever side is higher.
  final results = <TournamentMatchResult>[
    for (final m in matches.where(_isStandingsCounted))
      _resultFromMatch(m),
  ];

  return computeStandings(
    participantIds: participantIds,
    results: results,
    tiebreaker: const TiebreakerChain(<TiebreakerCriterion>[
      TiebreakerCriterion.totalPoints,
      TiebreakerCriterion.wins,
      TiebreakerCriterion.buchholzMinusH2H,
      TiebreakerCriterion.kubbDifference,
    ]),
  );
});

bool _isStandingsCounted(TournamentMatchRef m) {
  return m.status == TournamentMatchStatus.finalized ||
      m.status == TournamentMatchStatus.overridden;
}

TournamentMatchResult _resultFromMatch(TournamentMatchRef m) {
  final a = m.participantA!.value;
  final b = m.participantB?.value;
  final sA = m.finalScoreA ?? 0;
  final sB = m.finalScoreB ?? 0;
  final winner = sA >= sB ? SetWinner.teamA : SetWinner.teamB;
  return TournamentMatchResult(
    participantA: a,
    participantB: b,
    score: MatchEkcScore(<SetScore>[
      SetScore(
        basekubbsKnockedByA: sA,
        basekubbsKnockedByB: sB,
        winner: winner,
      ),
    ]),
  );
}
