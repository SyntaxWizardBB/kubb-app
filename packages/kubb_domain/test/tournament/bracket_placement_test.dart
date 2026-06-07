import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

/// Builds a `winners` KO match row (loser = the non-winner participant).
KoMatchRow winners({
  required int round,
  required int position,
  required String a,
  required String b,
  required String winner,
}) =>
    (
      roundNumber: round,
      bracketPosition: position,
      phase: BracketPhase.winners,
      participantA: a,
      participantB: b,
      winnerParticipantId: winner,
      isBye: false,
    );

KoMatchRow finals({
  required String a,
  required String b,
  required String winner,
  int round = 99,
}) =>
    (
      roundNumber: round,
      bracketPosition: 1,
      phase: BracketPhase.finals,
      participantA: a,
      participantB: b,
      winnerParticipantId: winner,
      isBye: false,
    );

KoMatchRow thirdPlace({
  required String a,
  required String b,
  required String winner,
}) =>
    (
      roundNumber: 99,
      bracketPosition: 1,
      phase: BracketPhase.thirdPlace,
      participantA: a,
      participantB: b,
      winnerParticipantId: winner,
      isBye: false,
    );

void main() {
  group('singleElimFinalTiers', () {
    // --- T1: 8er with third-place playoff, no tail. ---
    test('T1: 8 players with third-place match, no preliminary tail', () {
      // prelimRanking = the 8 KO participants (best first).
      final prelim = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
      // Quarterfinal (R1, 4 matches): winners p1,p2,p3,p4; losers p8,p7,p6,p5.
      // Semifinal (R2, 2 matches): winners p1,p2; losers p3,p4.
      // Finals: p1 beats p2. Third place: p3 beats p4.
      final ko = <KoMatchRow>[
        winners(round: 1, position: 1, a: 'p1', b: 'p8', winner: 'p1'),
        winners(round: 1, position: 2, a: 'p2', b: 'p7', winner: 'p2'),
        winners(round: 1, position: 3, a: 'p3', b: 'p6', winner: 'p3'),
        winners(round: 1, position: 4, a: 'p4', b: 'p5', winner: 'p4'),
        winners(round: 2, position: 1, a: 'p1', b: 'p4', winner: 'p1'),
        winners(round: 2, position: 2, a: 'p2', b: 'p3', winner: 'p2'),
        finals(a: 'p1', b: 'p2', winner: 'p1'),
        thirdPlace(a: 'p3', b: 'p4', winner: 'p3'),
      ];

      final result =
          singleElimFinalTiers(koMatches: ko, prelimRanking: prelim);

      expect(result.koRankCount, 8);
      expect(result.tiers, [
        ['p1'],
        ['p2'],
        ['p3'],
        ['p4'],
        // The 4 quarterfinal losers, stable by prelim order: p5,p6,p7,p8.
        ['p5', 'p6', 'p7', 'p8'],
      ]);
      expect(result.tiers.map((t) => t.length), [1, 1, 1, 1, 4]);
    });

    // --- T1b: end-to-end chaining into computeFinalRanking. ---
    test('T1b: end-to-end chaining via computeFinalRanking (ranks + points)',
        () {
      final prelim = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
      final ko = <KoMatchRow>[
        winners(round: 1, position: 1, a: 'p1', b: 'p8', winner: 'p1'),
        winners(round: 1, position: 2, a: 'p2', b: 'p7', winner: 'p2'),
        winners(round: 1, position: 3, a: 'p3', b: 'p6', winner: 'p3'),
        winners(round: 1, position: 4, a: 'p4', b: 'p5', winner: 'p4'),
        winners(round: 2, position: 1, a: 'p1', b: 'p4', winner: 'p1'),
        winners(round: 2, position: 2, a: 'p2', b: 'p3', winner: 'p2'),
        finals(a: 'p1', b: 'p2', winner: 'p1'),
        thirdPlace(a: 'p3', b: 'p4', winner: 'p3'),
      ];
      final result =
          singleElimFinalTiers(koMatches: ko, prelimRanking: prelim);

      const ctx = SkvTournamentContext(fieldSize: 8, league: SkvLeague.a);
      final placements = computeFinalRanking(
        ctx: ctx,
        tiers: result.tiers,
        koRankCount: result.koRankCount,
      );

      final ranks = placements.map((p) => p.rank).toList();
      expect(ranks, [1, 2, 3, 4, 5, 5, 5, 5]);

      // Points consistent with skvPointsForPlacement: W=5*8+50=90.
      final w = skvWinnerPoints(ctx);
      expect(w, 90);
      final byId = {for (final p in placements) p.participantId: p.points};
      expect(byId['p1'], (w * 1.0).round());
      expect(byId['p2'], (w * 0.8).round());
      expect(byId['p3'], (w * 0.65).round());
      expect(byId['p4'], (w * 0.5).round());
      // Rank 5 (tier 1): round(W * 0.25).
      final r5 = (w * 0.25).round();
      expect(byId['p5'], r5);
      expect(byId['p6'], r5);
      expect(byId['p7'], r5);
      expect(byId['p8'], r5);

      // All four rank-5 entries share identical points.
      final rank5Points =
          placements.where((p) => p.rank == 5).map((p) => p.points).toSet();
      expect(rank5Points.length, 1);

      // Strictly decreasing across ranks 1->5.
      expect(byId['p1']! > byId['p2']!, isTrue);
      expect(byId['p2']! > byId['p3']!, isTrue);
      expect(byId['p3']! > byId['p4']!, isTrue);
      expect(byId['p4']! > byId['p5']!, isTrue);
    });

    // --- T2: 8er without third-place match. ---
    test('T2: 8 players without third-place match (semifinal losers share 3)',
        () {
      final prelim = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
      final ko = <KoMatchRow>[
        winners(round: 1, position: 1, a: 'p1', b: 'p8', winner: 'p1'),
        winners(round: 1, position: 2, a: 'p2', b: 'p7', winner: 'p2'),
        winners(round: 1, position: 3, a: 'p3', b: 'p6', winner: 'p3'),
        winners(round: 1, position: 4, a: 'p4', b: 'p5', winner: 'p4'),
        winners(round: 2, position: 1, a: 'p1', b: 'p4', winner: 'p1'),
        winners(round: 2, position: 2, a: 'p2', b: 'p3', winner: 'p2'),
        finals(a: 'p1', b: 'p2', winner: 'p1'),
      ];

      final result =
          singleElimFinalTiers(koMatches: ko, prelimRanking: prelim);

      expect(result.koRankCount, 8);
      expect(result.tiers, [
        ['p1'],
        ['p2'],
        ['p3', 'p4'], // semifinal losers, shared rank 3
        ['p5', 'p6', 'p7', 'p8'], // quarterfinal losers
      ]);
      expect(result.tiers.map((t) => t.length), [1, 1, 2, 4]);

      const ctx = SkvTournamentContext(fieldSize: 8, league: SkvLeague.a);
      final ranks = computeFinalRanking(
        ctx: ctx,
        tiers: result.tiers,
        koRankCount: result.koRankCount,
      ).map((p) => p.rank).toList();
      expect(ranks, [1, 2, 3, 3, 5, 5, 5, 5]);
    });

    // --- T3: 16er with a preliminary tail. ---
    test('T3: 16 KO players + 4 non-qualified (N=20)', () {
      // Build prelim explicitly: 16 KO participants k01..k16 then tail t1..t4.
      final koIds = [
        for (var i = 1; i <= 16; i++) 'k${i.toString().padLeft(2, '0')}',
      ];
      final tail = ['t1', 't2', 't3', 't4'];
      final prelim = [...koIds, ...tail];

      // Round 1 (R16, 8 matches): seed i beats seed 17-i.
      // Winners: k01..k08, losers k16..k09 (the higher-numbered, worse seeds).
      final ko = <KoMatchRow>[
        for (var i = 1; i <= 8; i++)
          winners(
            round: 1,
            position: i,
            a: 'k${i.toString().padLeft(2, '0')}',
            b: 'k${(17 - i).toString().padLeft(2, '0')}',
            winner: 'k${i.toString().padLeft(2, '0')}',
          ),
        // Round 2 (QF, 4 matches): k01 vs k08, k02 vs k07, k03 vs k06, k04 vs k05.
        winners(round: 2, position: 1, a: 'k01', b: 'k08', winner: 'k01'),
        winners(round: 2, position: 2, a: 'k02', b: 'k07', winner: 'k02'),
        winners(round: 2, position: 3, a: 'k03', b: 'k06', winner: 'k03'),
        winners(round: 2, position: 4, a: 'k04', b: 'k05', winner: 'k04'),
        // Round 3 (SF, 2 matches): k01 vs k04, k02 vs k03.
        winners(round: 3, position: 1, a: 'k01', b: 'k04', winner: 'k01'),
        winners(round: 3, position: 2, a: 'k02', b: 'k03', winner: 'k02'),
        finals(a: 'k01', b: 'k02', winner: 'k01'),
        thirdPlace(a: 'k03', b: 'k04', winner: 'k03'),
      ];

      final result =
          singleElimFinalTiers(koMatches: ko, prelimRanking: prelim);

      expect(result.koRankCount, 16);

      // KO tiers: finals (1,2), thirdPlace (3,4), then winners desc R2 then R1.
      // R3 (semifinal) is covered by thirdPlace and must NOT reappear.
      expect(result.tiers[0], ['k01']); // rank 1
      expect(result.tiers[1], ['k02']); // rank 2
      expect(result.tiers[2], ['k03']); // rank 3
      expect(result.tiers[3], ['k04']); // rank 4
      // QF losers (R2): k05,k06,k07,k08 (sorted by prelim).
      expect(result.tiers[4], ['k05', 'k06', 'k07', 'k08']);
      // R16 losers (R1): k09..k16 (sorted by prelim).
      expect(result.tiers[5],
          ['k09', 'k10', 'k11', 'k12', 'k13', 'k14', 'k15', 'k16']);
      // Then 4 singleton tiers for the non-qualified, in prelim order.
      expect(result.tiers.sublist(6), [
        ['t1'],
        ['t2'],
        ['t3'],
        ['t4'],
      ]);

      // Sum of tier sizes == 20.
      final total =
          result.tiers.fold<int>(0, (s, t) => s + t.length);
      expect(total, 20);

      const ctx = SkvTournamentContext(fieldSize: 20, league: SkvLeague.a);
      final placements = computeFinalRanking(
        ctx: ctx,
        tiers: result.tiers,
        koRankCount: result.koRankCount,
      );
      final byId = {for (final p in placements) p.participantId: p.rank};
      // Non-qualified get ranks 17..20 in prelim order.
      expect(byId['t1'], 17);
      expect(byId['t2'], 18);
      expect(byId['t3'], 19);
      expect(byId['t4'], 20);
    });

    // --- T4: BYE produces no loser. ---
    test('T4: a BYE round-1 match produces no loser entry', () {
      final prelim = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
      // p1 advances via a BYE in R1 (isBye == true). No loser from that match.
      final ko = <KoMatchRow>[
        (
          roundNumber: 1,
          bracketPosition: 1,
          phase: BracketPhase.winners,
          participantA: 'p1',
          participantB: null,
          winnerParticipantId: 'p1',
          isBye: true,
        ),
        winners(round: 1, position: 2, a: 'p2', b: 'p7', winner: 'p2'),
        winners(round: 1, position: 3, a: 'p3', b: 'p6', winner: 'p3'),
        winners(round: 1, position: 4, a: 'p4', b: 'p5', winner: 'p4'),
        winners(round: 2, position: 1, a: 'p1', b: 'p4', winner: 'p1'),
        winners(round: 2, position: 2, a: 'p2', b: 'p3', winner: 'p2'),
        finals(a: 'p1', b: 'p2', winner: 'p1'),
        thirdPlace(a: 'p3', b: 'p4', winner: 'p3'),
      ];

      final result =
          singleElimFinalTiers(koMatches: ko, prelimRanking: prelim);

      // The bye-passed participant (p1) never appears as a loser.
      final allLoserTierIds = result.tiers
          .where((t) => t.length > 1 || result.tiers.indexOf(t) >= 4)
          .expand((t) => t)
          .toList();
      expect(allLoserTierIds.contains('p1'), isFalse);

      // The R1 quarterfinal tier holds only the real R1 losers: p5,p6,p7
      // (the BYE match contributed nothing). p8 never entered a real match, so
      // it is a non-qualified preliminary-tail entry appended last; only p1..p7
      // are real KO participants here.
      expect(result.koRankCount, 7);
      // KO tiers: [p1],[p2],[p3],[p4],[p5,p6,p7]; then tail [p8].
      expect(result.tiers, [
        ['p1'],
        ['p2'],
        ['p3'],
        ['p4'],
        ['p5', 'p6', 'p7'],
        ['p8'],
      ]);
    });

    // --- T5: validation, empty. ---
    test('T5: empty koMatches throws ArgumentError', () {
      expect(
        () => singleElimFinalTiers(
          koMatches: const <KoMatchRow>[],
          prelimRanking: const ['p1'],
        ),
        throwsArgumentError,
      );
    });

    // --- T6: validation, missing KO participant. ---
    test('T6: a KO participant missing from prelimRanking throws', () {
      final ko = <KoMatchRow>[
        finals(a: 'p1', b: 'p2', winner: 'p1'),
      ];
      expect(
        () => singleElimFinalTiers(
          koMatches: ko,
          prelimRanking: const ['p1'], // p2 missing
        ),
        throwsArgumentError,
      );
    });

    // --- T7: validation, duplicate in prelimRanking. ---
    test('T7: duplicate in prelimRanking throws', () {
      final ko = <KoMatchRow>[
        finals(a: 'p1', b: 'p2', winner: 'p1'),
      ];
      expect(
        () => singleElimFinalTiers(
          koMatches: ko,
          prelimRanking: const ['p1', 'p2', 'p1'],
        ),
        throwsArgumentError,
      );
    });

    // --- T7b: validation, present-but-incomplete third-place match. ---
    test('T7b: present but incomplete third-place match throws', () {
      final prelim = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
      final ko = <KoMatchRow>[
        winners(round: 1, position: 1, a: 'p1', b: 'p8', winner: 'p1'),
        winners(round: 1, position: 2, a: 'p2', b: 'p7', winner: 'p2'),
        winners(round: 1, position: 3, a: 'p3', b: 'p6', winner: 'p3'),
        winners(round: 1, position: 4, a: 'p4', b: 'p5', winner: 'p4'),
        winners(round: 2, position: 1, a: 'p1', b: 'p4', winner: 'p1'),
        winners(round: 2, position: 2, a: 'p2', b: 'p3', winner: 'p2'),
        finals(a: 'p1', b: 'p2', winner: 'p1'),
        // Third-place match exists but has no winner yet.
        (
          roundNumber: 99,
          bracketPosition: 1,
          phase: BracketPhase.thirdPlace,
          participantA: 'p3',
          participantB: 'p4',
          winnerParticipantId: null,
          isBye: false,
        ),
      ];
      expect(
        () => singleElimFinalTiers(koMatches: ko, prelimRanking: prelim),
        throwsArgumentError,
      );
    });

    // --- T8: determinism under permutation. ---
    test('T8: identical output regardless of koMatches order', () {
      final prelim = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
      final ko = <KoMatchRow>[
        winners(round: 1, position: 1, a: 'p1', b: 'p8', winner: 'p1'),
        winners(round: 1, position: 2, a: 'p2', b: 'p7', winner: 'p2'),
        winners(round: 1, position: 3, a: 'p3', b: 'p6', winner: 'p3'),
        winners(round: 1, position: 4, a: 'p4', b: 'p5', winner: 'p4'),
        winners(round: 2, position: 1, a: 'p1', b: 'p4', winner: 'p1'),
        winners(round: 2, position: 2, a: 'p2', b: 'p3', winner: 'p2'),
        finals(a: 'p1', b: 'p2', winner: 'p1'),
        thirdPlace(a: 'p3', b: 'p4', winner: 'p3'),
      ];

      final base = singleElimFinalTiers(koMatches: ko, prelimRanking: prelim);
      final shuffled = ko.reversed.toList();
      final res2 =
          singleElimFinalTiers(koMatches: shuffled, prelimRanking: prelim);
      // Another arbitrary permutation.
      final perm = [ko[4], ko[0], ko[7], ko[2], ko[6], ko[1], ko[5], ko[3]];
      final res3 =
          singleElimFinalTiers(koMatches: perm, prelimRanking: prelim);

      expect(res2.tiers, base.tiers);
      expect(res2.koRankCount, base.koRankCount);
      expect(res3.tiers, base.tiers);
      expect(res3.koRankCount, base.koRankCount);
    });

    // --- T9: general end-to-end (rank jumps + shared ranks identical pts). ---
    test('T9: end-to-end ranks/points incl. shared-rank identical points', () {
      final prelim = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
      final ko = <KoMatchRow>[
        winners(round: 1, position: 1, a: 'a', b: 'h', winner: 'a'),
        winners(round: 1, position: 2, a: 'b', b: 'g', winner: 'b'),
        winners(round: 1, position: 3, a: 'c', b: 'f', winner: 'c'),
        winners(round: 1, position: 4, a: 'd', b: 'e', winner: 'd'),
        winners(round: 2, position: 1, a: 'a', b: 'd', winner: 'a'),
        winners(round: 2, position: 2, a: 'b', b: 'c', winner: 'b'),
        finals(a: 'a', b: 'b', winner: 'a'),
        // No third-place: c,d share rank 3.
      ];
      final result =
          singleElimFinalTiers(koMatches: ko, prelimRanking: prelim);

      const ctx = SkvTournamentContext(fieldSize: 8, league: SkvLeague.a);
      final placements = computeFinalRanking(
        ctx: ctx,
        tiers: result.tiers,
        koRankCount: result.koRankCount,
      );
      final byId = {for (final p in placements) p.participantId: p};

      // Competition ranking with the size-2 shared tier at rank 3 => next jump
      // by 2 to rank 5.
      expect(byId['a']!.rank, 1);
      expect(byId['b']!.rank, 2);
      expect(byId['c']!.rank, 3);
      expect(byId['d']!.rank, 3);
      expect(byId['e']!.rank, 5);

      // Shared rank 3 => identical points.
      expect(byId['c']!.points, byId['d']!.points);
      // Shared rank 5 => identical points across all four.
      final r5 = placements.where((p) => p.rank == 5).map((p) => p.points);
      expect(r5.toSet().length, 1);
    });
  });
}
