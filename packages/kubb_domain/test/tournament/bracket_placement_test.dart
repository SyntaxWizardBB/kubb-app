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

/// Builds a `wb` (winner-bracket) KO match row. WB losses are NEVER an
/// elimination (the loser drops into the loser bracket), so these rows never
/// produce a tier on their own.
KoMatchRow wb({
  required int round,
  required int position,
  required String a,
  required String b,
  required String winner,
}) =>
    (
      roundNumber: round,
      bracketPosition: position,
      phase: BracketPhase.wb,
      participantA: a,
      participantB: b,
      winnerParticipantId: winner,
      isBye: false,
    );

/// Builds an `lb` (loser-bracket) KO match row in [round]. The loser of an lb
/// match is eliminated for real and forms part of that lb round's tier.
KoMatchRow lb({
  required int round,
  required int position,
  required String a,
  required String b,
  required String winner,
}) =>
    (
      roundNumber: round,
      bracketPosition: position,
      phase: BracketPhase.lb,
      participantA: a,
      participantB: b,
      winnerParticipantId: winner,
      isBye: false,
    );

/// Builds the `grandFinal` match row (phase-local `roundNumber == 1`).
KoMatchRow grandFinal({
  required String a,
  required String b,
  required String winner,
}) =>
    (
      roundNumber: 1,
      bracketPosition: 1,
      phase: BracketPhase.grandFinal,
      participantA: a,
      participantB: b,
      winnerParticipantId: winner,
      isBye: false,
    );

/// Builds the `grandFinalReset` match row (phase-local `roundNumber == 1`).
/// Pass `winner: null` to model an incomplete reset.
KoMatchRow grandFinalReset({
  required String a,
  required String b,
  required String? winner,
}) =>
    (
      roundNumber: 1,
      bracketPosition: 1,
      phase: BracketPhase.grandFinalReset,
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

  group('doubleElimFinalTiers', () {
    // Shared 8-player double-elim fixture (WB 3 rounds, LB 4 rounds = 2*(3-1)).
    //
    // Bracket form (who loses where):
    //   WB-R1 (4 matches): p1>p8, p2>p7, p3>p6, p4>p5
    //     -> WB-R1 losers p8,p7,p6,p5 drop to LB-R1.
    //   WB-R2 (2 matches): p1>p4, p2>p3
    //     -> WB-R2 losers p4,p3 drop to LB-R2 (major).
    //   WB-R3 / WB final (1 match): p1>p2  (p1 = WB champion)
    //     -> WB-R3 loser p2 drops to LB-R4 (LB final).
    //   LB-R1 (2 matches, minor): p5>p8, p6>p7  -> losers p8,p7.
    //   LB-R2 (2 matches, major): p4>p5, p3>p6  -> losers p5,p6.
    //   LB-R3 (1 match,  minor): p3>p4          -> loser p4.
    //   LB-R4 (1 match,  LB final): p2>p3       -> loser p3 (p2 = LB champion).
    //   Grand final: WB champ p1 vs LB champ p2.
    //
    // LB-round elimination order (descending round = better rank):
    //   LB-R4 loser p3 -> rank 3
    //   LB-R3 loser p4 -> rank 4
    //   LB-R2 losers p5,p6 -> shared tier (rank 5)
    //   LB-R1 losers p7,p8 -> shared tier (rank 7)
    List<KoMatchRow> deWbAndLb() => <KoMatchRow>[
          // WB.
          wb(round: 1, position: 1, a: 'p1', b: 'p8', winner: 'p1'),
          wb(round: 1, position: 2, a: 'p2', b: 'p7', winner: 'p2'),
          wb(round: 1, position: 3, a: 'p3', b: 'p6', winner: 'p3'),
          wb(round: 1, position: 4, a: 'p4', b: 'p5', winner: 'p4'),
          wb(round: 2, position: 1, a: 'p1', b: 'p4', winner: 'p1'),
          wb(round: 2, position: 2, a: 'p2', b: 'p3', winner: 'p2'),
          wb(round: 3, position: 1, a: 'p1', b: 'p2', winner: 'p1'),
          // LB.
          lb(round: 1, position: 1, a: 'p5', b: 'p8', winner: 'p5'),
          lb(round: 1, position: 2, a: 'p6', b: 'p7', winner: 'p6'),
          lb(round: 2, position: 1, a: 'p4', b: 'p5', winner: 'p4'),
          lb(round: 2, position: 2, a: 'p3', b: 'p6', winner: 'p3'),
          lb(round: 3, position: 1, a: 'p3', b: 'p4', winner: 'p3'),
          lb(round: 4, position: 1, a: 'p2', b: 'p3', winner: 'p2'),
        ];

    // --- D1: 8er double-elim WITHOUT reset (WB champ wins grand final). ---
    test('D1: 8er without reset, decider=grandFinal, LB tiers descending', () {
      final prelim = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
      // No grandFinalReset: WB champ p1 beats LB champ p2 in the grand final.
      final ko = <KoMatchRow>[
        ...deWbAndLb(),
        grandFinal(a: 'p1', b: 'p2', winner: 'p1'),
      ];

      final result = doubleElimFinalTiers(koMatches: ko, prelimRanking: prelim);

      expect(result.koRankCount, 8);
      // Decider = grandFinal: rank1=p1, rank2=p2; then LB rounds 4,3,2,1.
      expect(result.tiers, [
        ['p1'], // rank 1: GF winner
        ['p2'], // rank 2: GF loser
        ['p3'], // rank 3: LB-R4 (LB final) loser
        ['p4'], // rank 4: LB-R3 loser
        ['p5', 'p6'], // LB-R2 losers, shared
        ['p7', 'p8'], // LB-R1 losers, shared
      ]);

      // WB matches produce NO tier: WB losers appear only via LB tiers, once.
      final flat = result.tiers.expand((t) => t).toList();
      expect(flat.toSet().length, flat.length, reason: 'no duplicate in tiers');
      expect(flat.toSet(), prelim.toSet());

      // Sum of tier sizes == 8.
      expect(result.tiers.fold<int>(0, (s, t) => s + t.length), 8);

      // --- End-to-end via computeFinalRanking. ---
      const ctx = SkvTournamentContext(fieldSize: 8, league: SkvLeague.a);
      final placements = computeFinalRanking(
        ctx: ctx,
        tiers: result.tiers,
        koRankCount: result.koRankCount,
      );
      final ranks = placements.map((p) => p.rank).toList();
      // Competition ranking: 1,2,3,4 then size-2 tier at 5, then size-2 at 7.
      expect(ranks, [1, 2, 3, 4, 5, 5, 7, 7]);

      final byId = {for (final p in placements) p.participantId: p};
      // Shared LB-R2 rank => identical points.
      expect(byId['p5']!.points, byId['p6']!.points);
      // Shared LB-R1 rank => identical points.
      expect(byId['p7']!.points, byId['p8']!.points);

      // Monotone (non-increasing) points across the ranks.
      final pointsByRank = <int, int>{
        for (final p in placements) p.rank: p.points,
      };
      final orderedRanks = pointsByRank.keys.toList()..sort();
      for (var i = 1; i < orderedRanks.length; i++) {
        expect(
          pointsByRank[orderedRanks[i]]! <= pointsByRank[orderedRanks[i - 1]]!,
          isTrue,
          reason: 'points must not increase down the ranking',
        );
      }
      // Strictly decreasing across the singleton ranks 1->2->3->4.
      expect(byId['p1']!.points > byId['p2']!.points, isTrue);
      expect(byId['p2']!.points > byId['p3']!.points, isTrue);
      expect(byId['p3']!.points > byId['p4']!.points, isTrue);
    });

    // --- D2: 8er double-elim WITH reset (grandFinalReset complete). ---
    test('D2: 8er with complete reset, decider=reset, grandFinal ignored', () {
      final prelim = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
      // LB champ p2 wins the grand final first (forces the reset); the reset is
      // then played out and is complete. We let p1 win the reset (title).
      final ko = <KoMatchRow>[
        ...deWbAndLb(),
        grandFinal(a: 'p1', b: 'p2', winner: 'p2'), // p1 loses GF -> reset
        grandFinalReset(a: 'p1', b: 'p2', winner: 'p1'), // decider
      ];

      final result = doubleElimFinalTiers(koMatches: ko, prelimRanking: prelim);

      expect(result.koRankCount, 8);
      // Decider = reset: rank1=p1 (reset winner), rank2=p2 (reset loser).
      // The grandFinal match is IGNORED: its loser p1 gets NO separate tier.
      expect(result.tiers, [
        ['p1'], // rank 1: reset winner
        ['p2'], // rank 2: reset loser
        ['p3'],
        ['p4'],
        ['p5', 'p6'],
        ['p7', 'p8'],
      ]);

      // No participant appears twice across tiers (grandFinal not re-emitted).
      final flat = result.tiers.expand((t) => t).toList();
      expect(flat.toSet().length, flat.length);
      expect(result.tiers.fold<int>(0, (s, t) => s + t.length), 8);
    });

    // --- D3: LB-round grouping => two losers of one lb round share a rank. ---
    test('D3: two losers of the same lb round form one shared-rank tier', () {
      // Minimal-but-valid: the shared rank comes from LB-R2 (two real losers
      // p5,p6). Asserted directly on the tier (one tier, size 2) and end-to-end
      // (identical rank + identical points). Reuses the D1 fixture.
      final prelim = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
      final ko = <KoMatchRow>[
        ...deWbAndLb(),
        grandFinal(a: 'p1', b: 'p2', winner: 'p1'),
      ];

      final result = doubleElimFinalTiers(koMatches: ko, prelimRanking: prelim);

      // LB-R2 losers p5,p6 fall into ONE tier (not two), sorted by prelim.
      expect(result.tiers[4], ['p5', 'p6']);

      const ctx = SkvTournamentContext(fieldSize: 8, league: SkvLeague.a);
      final placements = computeFinalRanking(
        ctx: ctx,
        tiers: result.tiers,
        koRankCount: result.koRankCount,
      );
      final byId = {for (final p in placements) p.participantId: p};
      expect(byId['p5']!.rank, byId['p6']!.rank);
      expect(byId['p5']!.points, byId['p6']!.points);
    });

    // --- D4: preliminary tail (8 KO + 2 non-qualified, N=10). ---
    test('D4: prelim tail of 2 non-qualified gets ranks 9 and 10', () {
      // Same 8-player KO as D1; prelim has two extra non-qualified t1,t2 that
      // never appear in any match.
      final prelim = [
        'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 't1', 't2', //
      ];
      final ko = <KoMatchRow>[
        ...deWbAndLb(),
        grandFinal(a: 'p1', b: 'p2', winner: 'p1'),
      ];

      final result = doubleElimFinalTiers(koMatches: ko, prelimRanking: prelim);

      expect(result.koRankCount, 8);
      // The two non-qualified are the last two singleton tiers, in prelim order.
      expect(result.tiers.sublist(result.tiers.length - 2), [
        ['t1'],
        ['t2'],
      ]);
      expect(result.tiers.fold<int>(0, (s, t) => s + t.length), 10);

      const ctx = SkvTournamentContext(fieldSize: 10, league: SkvLeague.a);
      final placements = computeFinalRanking(
        ctx: ctx,
        tiers: result.tiers,
        koRankCount: result.koRankCount,
      );
      final byId = {for (final p in placements) p.participantId: p.rank};
      expect(byId['t1'], 9);
      expect(byId['t2'], 10);
    });

    // --- D5: a BYE in LB-R1 produces no loser. ---
    test('D5: a BYE LB-R1 match produces no loser entry', () {
      // 8-player KO but the LB-R1 match that would feed p8 is a server-marked
      // BYE (ADR-0027 §1.5): p5 passes through LB-R1 via BYE, p8 is not a real
      // LB participant. To keep the field at 8 distinct KO participants, p8
      // still loses its WB-R1 match (so it is a real participant overall) but
      // never appears as an LB loser.
      //
      // Bracket form: identical to deWbAndLb() EXCEPT LB-R1 position 1 is a BYE
      // (participantB == null, isBye == true) carrying p5 onward — so LB-R1 has
      // only ONE real loser (p7 from position 2).
      final prelim = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
      final ko = <KoMatchRow>[
        // WB unchanged (p8 loses WB-R1 -> real participant, counts for rank).
        wb(round: 1, position: 1, a: 'p1', b: 'p8', winner: 'p1'),
        wb(round: 1, position: 2, a: 'p2', b: 'p7', winner: 'p2'),
        wb(round: 1, position: 3, a: 'p3', b: 'p6', winner: 'p3'),
        wb(round: 1, position: 4, a: 'p4', b: 'p5', winner: 'p4'),
        wb(round: 2, position: 1, a: 'p1', b: 'p4', winner: 'p1'),
        wb(round: 2, position: 2, a: 'p2', b: 'p3', winner: 'p2'),
        wb(round: 3, position: 1, a: 'p1', b: 'p2', winner: 'p1'),
        // LB-R1 position 1: BYE (p5 advances, no loser produced).
        (
          roundNumber: 1,
          bracketPosition: 1,
          phase: BracketPhase.lb,
          participantA: 'p5',
          participantB: null,
          winnerParticipantId: 'p5',
          isBye: true,
        ),
        lb(round: 1, position: 2, a: 'p6', b: 'p7', winner: 'p6'),
        lb(round: 2, position: 1, a: 'p4', b: 'p5', winner: 'p4'),
        lb(round: 2, position: 2, a: 'p3', b: 'p6', winner: 'p3'),
        lb(round: 3, position: 1, a: 'p3', b: 'p4', winner: 'p3'),
        lb(round: 4, position: 1, a: 'p2', b: 'p3', winner: 'p2'),
        grandFinal(a: 'p1', b: 'p2', winner: 'p1'),
      ];

      final result = doubleElimFinalTiers(koMatches: ko, prelimRanking: prelim);

      expect(result.koRankCount, 8);
      // LB-R1 now yields only p7 (the BYE produced no loser, p8 absent there).
      expect(result.tiers, [
        ['p1'],
        ['p2'],
        ['p3'],
        ['p4'],
        ['p5', 'p6'],
        ['p7'], // only the single real LB-R1 loser
      ]);
      // p8 lost only its WB match (never an elimination) and never reaches LB,
      // so it appears in NO tier despite being a real KO participant.
      final flat = result.tiers.expand((t) => t).toSet();
      expect(flat.contains('p8'), isFalse);
    });

    // --- D6: validation, no grandFinal. ---
    test('D6: no grandFinal match throws ArgumentError', () {
      final prelim = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
      // wb/lb present but neither grandFinal nor reset.
      final ko = deWbAndLb();
      expect(
        () => doubleElimFinalTiers(koMatches: ko, prelimRanking: prelim),
        throwsArgumentError,
      );
    });

    // --- D7: validation, KO participant missing from prelimRanking. ---
    test('D7: a KO participant missing from prelimRanking throws', () {
      final ko = <KoMatchRow>[
        ...deWbAndLb(),
        grandFinal(a: 'p1', b: 'p2', winner: 'p1'),
      ];
      expect(
        () => doubleElimFinalTiers(
          koMatches: ko,
          prelimRanking: const ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'],
        ),
        throwsArgumentError,
      );
    });

    // --- D8: validation, empty koMatches. ---
    test('D8: empty koMatches throws ArgumentError', () {
      expect(
        () => doubleElimFinalTiers(
          koMatches: const <KoMatchRow>[],
          prelimRanking: const ['p1'],
        ),
        throwsArgumentError,
      );
    });

    // --- D9: validation, duplicate in prelimRanking. ---
    test('D9: duplicate in prelimRanking throws', () {
      final ko = <KoMatchRow>[
        ...deWbAndLb(),
        grandFinal(a: 'p1', b: 'p2', winner: 'p1'),
      ];
      expect(
        () => doubleElimFinalTiers(
          koMatches: ko,
          prelimRanking: const [
            'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'p1', //
          ],
        ),
        throwsArgumentError,
      );
    });

    // --- D10: validation, decider incomplete (no fallback reset->grandFinal).
    test('D10: present-but-incomplete reset throws (no fallback to GF)', () {
      final prelim = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
      // grandFinal is complete, but the reset exists WITHOUT a winner. The reset
      // is the decider and is incomplete => error, NOT a fallback to grandFinal.
      final ko = <KoMatchRow>[
        ...deWbAndLb(),
        grandFinal(a: 'p1', b: 'p2', winner: 'p2'),
        grandFinalReset(a: 'p1', b: 'p2', winner: null),
      ];
      expect(
        () => doubleElimFinalTiers(koMatches: ko, prelimRanking: prelim),
        throwsArgumentError,
      );
    });

    // --- D11: determinism under permutation of koMatches. ---
    test('D11: identical output regardless of koMatches order', () {
      final prelim = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
      final ko = <KoMatchRow>[
        ...deWbAndLb(),
        grandFinal(a: 'p1', b: 'p2', winner: 'p1'),
      ];

      final base = doubleElimFinalTiers(koMatches: ko, prelimRanking: prelim);
      final reversed = doubleElimFinalTiers(
        koMatches: ko.reversed.toList(),
        prelimRanking: prelim,
      );
      final shuffled = [...ko]..shuffle();
      final permuted =
          doubleElimFinalTiers(koMatches: shuffled, prelimRanking: prelim);

      expect(reversed.tiers, base.tiers);
      expect(reversed.koRankCount, base.koRankCount);
      expect(permuted.tiers, base.tiers);
      expect(permuted.koRankCount, base.koRankCount);
    });
  });
}
