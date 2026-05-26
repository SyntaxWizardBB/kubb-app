import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

ParticipantStats _stats(int i) => ParticipantStats(
    participantId: 'p${i + 1}',
    totalPoints: 8 - i,
    wins: 0,
    kubbsScored: 0,
    kubbsConceded: 0,
    opponentIds: const [],
    opponentTotalPointsLookup: const {},
    headToHeadLookup: const {});

String _topSeedWinner(BracketPairing p) =>
    (p.$1.seed <= p.$2.seed ? p.$1.participantId : p.$2.participantId)!;
String _other(BracketPairing p, String winner) =>
    p.$1.participantId == winner ? p.$2.participantId! : p.$1.participantId!;

void main() {
  test('M2.1 smoke: 8 participants → seeding → bracket → KO playthrough', () {
    // 8 stats with strictly descending totalPoints → seeding best-first.
    final stats = List<ParticipantStats>.generate(8, _stats);
    const chain = TiebreakerChain(<TiebreakerCriterion>[
      TiebreakerCriterion.totalPoints,
    ]);
    final seeded = seedFromStandings(stats, chain);
    expect(seeded, ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8']);

    // 8-bracket with third-place playoff: 3 winners rounds + 1 thirdPlace.
    final ko = Bracket.singleElimination(seeded, withThirdPlace: true)
        as SingleEliminationBracket;
    expect(ko.rounds, hasLength(4));
    expect(ko.rounds.where((r) => r.phase == BracketPhase.thirdPlace), hasLength(1));

    // Quarterfinals — top seed wins each → semifinalists [p1, p4, p3, p2].
    final qfWinners = [
      for (final p in ko.rounds.first.pairings) _topSeedWinner(p),
    ];
    expect(qfWinners, ['p1', 'p4', 'p3', 'p2']);

    // Project semifinalists into a fresh 4-bracket-with-thirdPlace; passing
    // them in seed order reproduces the matchups (seed1 vs seed4) and
    // (seed3 vs seed2) via the factory's recursive seeding.
    final semis = Bracket.singleElimination(
      const ['p1', 'p2', 'p3', 'p4'],
      withThirdPlace: true,
    ) as SingleEliminationBracket;
    final semiPairings = semis.rounds.first.pairings;
    expect(
      semiPairings.map((p) => {p.$1.participantId, p.$2.participantId}),
      [
        {'p1', 'p4'},
        {'p3', 'p2'},
      ],
    );

    // Halbfinale-Fill — top seed of each semi advances to the final.
    final finalists = [for (final p in semiPairings) _topSeedWinner(p)];
    final filled = semis
        .fill(round: 2, position: 1, participantId: finalists[0])
        .fill(round: 2, position: 2, participantId: finalists[1])
            as SingleEliminationBracket;

    // Final + third-place pairings yield the final rank 1–4.
    final finalPair = filled.rounds
        .firstWhere((r) => r.phase != BracketPhase.thirdPlace && r.number == 2)
        .pairings
        .single;
    final bronzePair = filled.rounds
        .firstWhere((r) => r.phase == BracketPhase.thirdPlace)
        .pairings
        .single;
    final rank1 = _topSeedWinner(finalPair);
    final rank3 = _topSeedWinner(bronzePair);
    expect(rank1, 'p1', reason: 'rank 1 = final winner');
    expect(_other(finalPair, rank1), 'p2', reason: 'rank 2 = final loser');
    expect(rank3, 'p3', reason: 'rank 3 = bronze winner');
    expect(_other(bronzePair, rank3), 'p4', reason: 'rank 4 = bronze loser');
  });
}
