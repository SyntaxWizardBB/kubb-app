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

void main() {
  test('M2.1 smoke: 8 participants → seeding → bracket → KO playthrough', () {
    // 8 stats with strictly descending totalPoints → seeding best-first.
    final stats = List<ParticipantStats>.generate(8, _stats);
    const chain = TiebreakerChain(<TiebreakerCriterion>[
      TiebreakerCriterion.totalPoints,
    ]);
    final seeded = seedFromStandings(stats, chain);
    expect(seeded, ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8']);

    // Seed-rank lookup (1 = top seed); persists across rounds since fill()
    // strips seed metadata when writing into placeholder rounds.
    final seedRank = <String, int>{
      for (var i = 0; i < seeded.length; i++) seeded[i]: i + 1,
    };
    String topSeed(String a, String b) =>
        seedRank[a]! <= seedRank[b]! ? a : b;
    String otherOf(BracketPairing p, String winner) =>
        p.$1.participantId == winner ? p.$2.participantId! : p.$1.participantId!;

    // 8-bracket with third-place playoff: 3 winners rounds + 1 thirdPlace.
    var ko = Bracket.singleElimination(seeded, withThirdPlace: true)
        as SingleEliminationBracket;
    expect(ko.rounds, hasLength(4));
    expect(ko.rounds.where((r) => r.phase == BracketPhase.thirdPlace),
        hasLength(1));

    // Quarterfinals — top seed wins each → semifinalists [p1, p4, p3, p2].
    final qfPairings = ko.rounds.first.pairings;
    final qfWinners = [
      for (final p in qfPairings)
        topSeed(p.$1.participantId!, p.$2.participantId!),
    ];
    expect(qfWinners, ['p1', 'p4', 'p3', 'p2']);
    for (var i = 0; i < qfWinners.length; i++) {
      // Semis live in round 2 — 2 pairings → positions 1..4.
      ko = ko.fill(round: 2, position: i + 1, participantId: qfWinners[i])
          as SingleEliminationBracket;
    }

    // Halbfinale-Auswertung — Top-Seed jedes Semi-Pairings zieht ins Finale.
    final semiPairings = ko.rounds[1].pairings;
    final finalists = [
      for (final p in semiPairings)
        topSeed(p.$1.participantId!, p.$2.participantId!),
    ];
    expect(finalists, ['p1', 'p2']);
    ko = ko.fill(round: 3, position: 1, participantId: finalists[0])
        .fill(round: 3, position: 2, participantId: finalists[1])
            as SingleEliminationBracket;

    // Final + third-place pairings yield the final rank 1–4.
    final finalPair = ko.rounds
        .firstWhere((r) => r.phase != BracketPhase.thirdPlace && r.number == 3)
        .pairings
        .single;
    final bronzePair = ko.rounds
        .firstWhere((r) => r.phase == BracketPhase.thirdPlace)
        .pairings
        .single;
    final rank1 = topSeed(
        finalPair.$1.participantId!, finalPair.$2.participantId!);
    final rank3 = topSeed(
        bronzePair.$1.participantId!, bronzePair.$2.participantId!);
    expect(rank1, 'p1', reason: 'rank 1 = final winner');
    expect(otherOf(finalPair, rank1), 'p2', reason: 'rank 2 = final loser');
    expect(rank3, 'p3', reason: 'rank 3 = bronze winner');
    expect(otherOf(bronzePair, rank3), 'p4', reason: 'rank 4 = bronze loser');
  });
}
