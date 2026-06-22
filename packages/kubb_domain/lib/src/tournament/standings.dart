import 'package:kubb_domain/src/ports/tournament_remote.dart';
import 'package:kubb_domain/src/tournament/ekc_score.dart';
import 'package:kubb_domain/src/tournament/tiebreaker.dart';
import 'package:meta/meta.dart';

/// One finished match in a tournament, used as input to standings calc.
///
/// If [participantB] is null, the match is a BYE: [participantA] advances
/// with the configured bye score and the [score] field is ignored.
@immutable
class TournamentMatchResult {
  const TournamentMatchResult({
    required this.participantA,
    required this.participantB,
    required this.score,
  });

  final String participantA;
  final String? participantB;
  final MatchEkcScore score;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentMatchResult &&
          other.participantA == participantA &&
          other.participantB == participantB &&
          other.score == score;
  @override
  int get hashCode => Object.hash(participantA, participantB, score);
  @override
  String toString() =>
      'TournamentMatchResult($participantA vs ${participantB ?? "BYE"})';
}

/// FF2 / Finding B: builds a [TournamentMatchResult] for the standings
/// input from a match's final score and — when available — the real
/// per-side set-win counts.
///
/// Both Dart standings callers (the authenticated match-list provider and
/// the anon public spectator screen) previously synthesised a SINGLE
/// [SetScore] from `finalScoreA/B`. In classic mode [computeStandings]
/// then derived `setsWon = 1/0` per match — i.e. MATCH wins — whereas the
/// server (`tournament_pool_standings`, CF2) sums real SET wins from
/// `tournament_set_score_proposals`. For best-of-3 the two diverge.
///
/// Set-win reconstruction is CLASSIC-ONLY. In classic mode the points are
/// the won sets, so when [setsWonA] / [setsWonB] are non-null (the RPCs now
/// project them) this reconstructs exactly that many won sets per side so
/// `MatchEkcScore.setsWonA/B` equals the server's `sets_won_a/_b` and the
/// classic standings match. The total basekubbs ([finalScoreA] /
/// [finalScoreB]) are placed in a single set so `kubbsScored/conceded`
/// stay identical to the previous behaviour and the kubb-difference
/// tiebreak is unaffected.
///
/// In EKC mode — or when [setsWonA] / [setsWonB] are null (older RPC
/// revision, realtime CDC row, or a match with no agreed sets) — it falls
/// back to the historical single-set synthesis: one set carrying the full
/// final score, winner = whichever side is higher. This is REQUIRED for
/// EKC: `pointsForA/B` is the per-set EKC contribution, and the historical
/// EKC standings were always computed over a single synthesised set, so
/// reconstructing multiple sets would change the EKC points. The classic
/// scoring branch ignores per-set basekubbs entirely (it reads setsWon),
/// so the multi-set reconstruction is safe there.
TournamentMatchResult tournamentMatchResultFromFinalScore({
  required String participantA,
  required String? participantB,
  required int finalScoreA,
  required int finalScoreB,
  required TournamentScoring scoring,
  int? setsWonA,
  int? setsWonB,
}) {
  // EKC, or no real per-side set wins -> historical single-set fallback.
  if (scoring != TournamentScoring.classic ||
      setsWonA == null ||
      setsWonB == null) {
    final winner =
        finalScoreA >= finalScoreB ? SetWinner.teamA : SetWinner.teamB;
    return TournamentMatchResult(
      participantA: participantA,
      participantB: participantB,
      score: MatchEkcScore(<SetScore>[
        SetScore(
          basekubbsKnockedByA: finalScoreA,
          basekubbsKnockedByB: finalScoreB,
          winner: winner,
        ),
      ]),
    );
  }

  // Real set wins available and at least one side won a set. Reconstruct
  // `setsWonA` sets won by A and `setsWonB` won by B so
  // MatchEkcScore.setsWonA/B == server sets_won. The full basekubb totals
  // live in exactly one set (the first) so the accumulated
  // kubbsScored/conceded equal finalScoreA/B unchanged.
  //
  // Degenerate 0:0: the RPC projected sets_won_a == sets_won_b == 0 (a
  // match finalised without any agreed set proposal). The server's classic
  // standings (tournament_pool_standings, CF2) award 0 points and count 0
  // kubbs for such a match — there is no agreed set to score. Mirror that
  // EXACTLY with an empty MatchEkcScore (no synthetic winner set, no
  // basekubbs) so client and server classic totals stay identical. (The
  // legacy null-fallback above still synthesises a winner set, which is the
  // correct behaviour when the real per-side counts are simply unknown.)
  if (setsWonA == 0 && setsWonB == 0) {
    return TournamentMatchResult(
      participantA: participantA,
      participantB: participantB,
      score: MatchEkcScore(const <SetScore>[]),
    );
  }

  final sets = <SetScore>[];
  var carriedKubbsA = false;
  void addSet(SetWinner winner) {
    final kubbsA = carriedKubbsA ? 0 : finalScoreA;
    final kubbsB = carriedKubbsA ? 0 : finalScoreB;
    carriedKubbsA = true;
    sets.add(SetScore(
      basekubbsKnockedByA: kubbsA,
      basekubbsKnockedByB: kubbsB,
      winner: winner,
    ));
  }

  // At least one of setsWonA / setsWonB is > 0 here (the 0:0 case returned
  // early above), so `sets` is guaranteed non-empty.
  for (var i = 0; i < setsWonA; i++) {
    addSet(SetWinner.teamA);
  }
  for (var i = 0; i < setsWonB; i++) {
    addSet(SetWinner.teamB);
  }

  return TournamentMatchResult(
    participantA: participantA,
    participantB: participantB,
    score: MatchEkcScore(sets),
  );
}

/// Points credited to a Schoch (Swiss) bye player: a full win, worth 16
/// (schoch-swiss spec §4.2). The credit lands in the bye player's total and
/// thereby feeds the Buchholz of every real opponent who faced them. Pass it
/// to [computeStandings] via `byeScoreForUnopposedParticipant` for a Schoch
/// preliminary; other formats keep their own bye handling (default 0).
const int schochByeScore = 16;

/// Bye credit a [format] grants an unopposed participant when its standings
/// are folded through [computeStandings]. Schoch (incl. its hybrid with a KO
/// stage) scores a bye as a full win ([schochByeScore]); every other format
/// keeps the historical zero. Pass the result straight into
/// `byeScoreForUnopposedParticipant`.
int schochByeScoreFor(TournamentFormat format) {
  switch (format) {
    case TournamentFormat.schoch:
    case TournamentFormat.schochThenKo:
      return schochByeScore;
    case TournamentFormat.roundRobin:
    case TournamentFormat.singleElimination:
    case TournamentFormat.roundRobinThenKo:
      return 0;
  }
}

class _Acc {
  int totalPoints = 0;
  int wins = 0;
  int kubbsScored = 0;
  int kubbsConceded = 0;
  final List<String> opponentIds = [];
  final Map<String, int> headToHead = {};
  final Map<String, int> scoreAgainst = {};
}

/// Pure ranking function (FR-RANK-3/-4). Computes per-participant stats from
/// confirmed match results, then sorts via [tiebreaker].
///
/// [scoring] (CF2 / ChangeSpec K04) selects how a match contributes points:
///
///  * [TournamentScoring.ekc] — the historical behaviour. Each side scores
///    its EKC total ([MatchEkcScore] `pointsForA` / `pointsForB`): 1 point
///    per basekubb + 3 per set win + king-outcome bonus.
///  * [TournamentScoring.classic] — "only the set win counts". Points come
///    solely from sets won ([MatchEkcScore] `setsWonA` / `setsWonB`);
///    basekubb counts are NOT point-bearing. `kubbsScored` / `kubbsConceded`
///    are still accumulated so the kubb-difference can act as a tiebreak, but
///    they do not feed `totalPoints`.
///
/// Defaults to [TournamentScoring.ekc] for backward compatibility with
/// existing call sites and tests.
List<ParticipantStats> computeStandings({
  required List<String> participantIds,
  required List<TournamentMatchResult> results,
  required TiebreakerChain tiebreaker,
  TournamentScoring scoring = TournamentScoring.ekc,
  int byeScoreForUnopposedParticipant = 0,
}) {
  final ids = participantIds.toSet();
  final accs = {for (final id in participantIds) id: _Acc()};
  void check(String id) {
    if (!ids.contains(id)) {
      throw ArgumentError('result references unknown participant: $id');
    }
  }

  for (final r in results) {
    check(r.participantA);
    if (r.participantB == null) {
      accs[r.participantA]!
        ..totalPoints += byeScoreForUnopposedParticipant
        ..wins += 1;
      continue;
    }
    check(r.participantB!);
    final a = accs[r.participantA]!;
    final b = accs[r.participantB!]!;
    final kA = r.score.sets.fold<int>(0, (s, x) => s + x.basekubbsKnockedByA);
    final kB = r.score.sets.fold<int>(0, (s, x) => s + x.basekubbsKnockedByB);
    final w = r.score.matchWinner;
    final d = w == null ? 0 : (w == SetWinner.teamA ? 1 : -1);
    // CF2: point source switches on the tournament scoring mode. EKC uses
    // the per-set EKC total; classic counts won sets only (basekubbs stay
    // out of the points and remain a tiebreak via kubbsScored/conceded).
    final (pointsA, pointsB) = switch (scoring) {
      TournamentScoring.ekc => (r.score.pointsForA, r.score.pointsForB),
      TournamentScoring.classic => (r.score.setsWonA, r.score.setsWonB),
    };
    a
      ..totalPoints += pointsA
      ..kubbsScored += kA
      ..kubbsConceded += kB
      ..wins += w == SetWinner.teamA ? 1 : 0
      ..opponentIds.add(r.participantB!);
    b
      ..totalPoints += pointsB
      ..kubbsScored += kB
      ..kubbsConceded += kA
      ..wins += w == SetWinner.teamB ? 1 : 0
      ..opponentIds.add(r.participantA);
    a.headToHead.update(r.participantB!, (v) => v + d, ifAbsent: () => d);
    b.headToHead.update(r.participantA, (v) => v - d, ifAbsent: () => -d);
    a.scoreAgainst
        .update(r.participantB!, (v) => v + pointsB, ifAbsent: () => pointsB);
    b.scoreAgainst
        .update(r.participantA, (v) => v + pointsA, ifAbsent: () => pointsA);
  }

  final totals = {for (final e in accs.entries) e.key: e.value.totalPoints};
  final stats = [
    for (final id in participantIds)
      ParticipantStats(
        participantId: id,
        totalPoints: accs[id]!.totalPoints,
        wins: accs[id]!.wins,
        kubbsScored: accs[id]!.kubbsScored,
        kubbsConceded: accs[id]!.kubbsConceded,
        opponentIds: List.unmodifiable(accs[id]!.opponentIds),
        opponentTotalPointsLookup: {
          for (final o in accs[id]!.opponentIds) o: totals[o] ?? 0,
        },
        headToHeadLookup: Map.unmodifiable(accs[id]!.headToHead),
        opponentScoreAgainstLookup:
            Map.unmodifiable(accs[id]!.scoreAgainst),
      ),
  ];
  return stats..sort(tiebreaker.compare);
}
