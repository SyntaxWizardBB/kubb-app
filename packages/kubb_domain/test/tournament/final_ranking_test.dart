import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('computeFinalRanking', () {
    test('clean 16-bracket: ranks and points match the worked example', () {
      const ctx = SkvTournamentContext(fieldSize: 16, league: SkvLeague.a);
      final result = computeFinalRanking(
        ctx: ctx,
        tiers: const <List<String>>[
          <String>['A'],
          <String>['B'],
          <String>['C'],
          <String>['D'],
          <String>['E', 'F', 'G', 'H'],
          <String>['I', 'J', 'K', 'L', 'M', 'N', 'O', 'P'],
        ],
        koRankCount: 16,
      );

      // Output covers every participant exactly once.
      expect(result.length, 16);

      SkvPlacement byId(String id) =>
          result.firstWhere((p) => p.participantId == id);

      // Ranks.
      expect(byId('A').rank, 1);
      expect(byId('B').rank, 2);
      expect(byId('C').rank, 3);
      expect(byId('D').rank, 4);
      for (final id in <String>['E', 'F', 'G', 'H']) {
        expect(byId(id).rank, 5, reason: '$id should be rank 5');
      }
      for (final id in <String>['I', 'J', 'K', 'L', 'M', 'N', 'O', 'P']) {
        expect(byId(id).rank, 9, reason: '$id should be rank 9');
      }

      // Points (W = 130).
      expect(byId('A').points, 130);
      expect(byId('B').points, 104);
      expect(byId('C').points, 85);
      expect(byId('D').points, 65);
      for (final id in <String>['E', 'F', 'G', 'H']) {
        expect(byId(id).points, 33, reason: '$id rank-5 tier');
      }
      for (final id in <String>['I', 'J', 'K', 'L', 'M', 'N', 'O', 'P']) {
        expect(byId(id).points, 16, reason: '$id rank-9 tier');
      }
    });

    test('tie at the top (no 3rd-place game): C and D both rank 3', () {
      const ctx = SkvTournamentContext(fieldSize: 16, league: SkvLeague.a);
      final result = computeFinalRanking(
        ctx: ctx,
        tiers: const <List<String>>[
          <String>['A'],
          <String>['B'],
          <String>['C', 'D'],
          <String>['E', 'F', 'G', 'H'],
          <String>['I', 'J', 'K', 'L', 'M', 'N', 'O', 'P'],
        ],
        koRankCount: 16,
      );

      SkvPlacement byId(String id) =>
          result.firstWhere((p) => p.participantId == id);

      expect(byId('C').rank, 3);
      expect(byId('D').rank, 3);
      // 0.65 * 130 = 84.5 -> 85.
      expect(byId('C').points, 85);
      expect(byId('D').points, 85);
      // Next tier jumps by the size of the tie (2): from rank 3 to rank 5.
      expect(byId('E').rank, 5);
    });

    test('preliminary tail: ranks 17..20 with strictly falling points', () {
      const ctx = SkvTournamentContext(fieldSize: 20, league: SkvLeague.a);
      final result = computeFinalRanking(
        ctx: ctx,
        tiers: const <List<String>>[
          <String>['A'],
          <String>['B'],
          <String>['C'],
          <String>['D'],
          <String>['E', 'F', 'G', 'H'],
          <String>['I', 'J', 'K', 'L', 'M', 'N', 'O', 'P'],
          <String>['Q'],
          <String>['R'],
          <String>['S'],
          <String>['T'],
        ],
        koRankCount: 16,
      );

      SkvPlacement byId(String id) =>
          result.firstWhere((p) => p.participantId == id);

      expect(byId('Q').rank, 17);
      expect(byId('R').rank, 18);
      expect(byId('S').rank, 19);
      expect(byId('T').rank, 20);

      // Strictly monotone falling tail.
      expect(byId('Q').points, greaterThan(byId('R').points));
      expect(byId('R').points, greaterThan(byId('S').points));
      expect(byId('S').points, greaterThan(byId('T').points));

      // Last rank equals the direct Phase-A value with the same pMin.
      const ctxRef = SkvTournamentContext(fieldSize: 20, league: SkvLeague.a);
      expect(
        byId('T').points,
        skvPointsForPlacement(ctx: ctxRef, placement: 20, koRankCount: 16),
      );
    });

    test('tie in the tail: shared rank and points', () {
      const ctx = SkvTournamentContext(fieldSize: 20, league: SkvLeague.a);
      final result = computeFinalRanking(
        ctx: ctx,
        tiers: const <List<String>>[
          <String>['A'],
          <String>['B'],
          <String>['C'],
          <String>['D'],
          <String>['E', 'F', 'G', 'H'],
          <String>['I', 'J', 'K', 'L', 'M', 'N', 'O', 'P'],
          <String>['Q'],
          <String>['R'],
          <String>['S', 'T'],
        ],
        koRankCount: 16,
      );

      SkvPlacement byId(String id) =>
          result.firstWhere((p) => p.participantId == id);

      expect(byId('S').rank, 19);
      expect(byId('T').rank, 19);
      expect(byId('S').points, byId('T').points);
    });

    test('determinism: two identical calls yield deeply equal lists', () {
      const ctx = SkvTournamentContext(fieldSize: 16, league: SkvLeague.a);
      const tiers = <List<String>>[
        <String>['A'],
        <String>['B'],
        <String>['C'],
        <String>['D'],
        <String>['E', 'F', 'G', 'H'],
        <String>['I', 'J', 'K', 'L', 'M', 'N', 'O', 'P'],
      ];
      final a = computeFinalRanking(ctx: ctx, tiers: tiers, koRankCount: 16);
      final b = computeFinalRanking(ctx: ctx, tiers: tiers, koRankCount: 16);

      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i], b[i], reason: 'entry $i must be equal');
        expect(a[i].participantId, b[i].participantId);
        expect(a[i].rank, b[i].rank);
        expect(a[i].points, b[i].points);
      }
    });

    test('output preserves tier order and within-tier id order', () {
      const ctx = SkvTournamentContext(fieldSize: 16, league: SkvLeague.a);
      final result = computeFinalRanking(
        ctx: ctx,
        tiers: const <List<String>>[
          <String>['A'],
          <String>['B'],
          <String>['C'],
          <String>['D'],
          <String>['E', 'F', 'G', 'H'],
          <String>['I', 'J', 'K', 'L', 'M', 'N', 'O', 'P'],
        ],
        koRankCount: 16,
      );
      final ids = result.map((p) => p.participantId).toList();
      expect(ids, <String>[
        'A', 'B', 'C', 'D', //
        'E', 'F', 'G', 'H', //
        'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', //
      ]);
    });

    test('pMin is respected: a different pMin changes the tail end', () {
      const ctx = SkvTournamentContext(fieldSize: 20, league: SkvLeague.a);
      const tiers = <List<String>>[
        <String>['A'],
        <String>['B'],
        <String>['C'],
        <String>['D'],
        <String>['E', 'F', 'G', 'H'],
        <String>['I', 'J', 'K', 'L', 'M', 'N', 'O', 'P'],
        <String>['Q'],
        <String>['R'],
        <String>['S'],
        <String>['T'],
      ];

      final defaultRun =
          computeFinalRanking(ctx: ctx, tiers: tiers, koRankCount: 16);
      final pMin5Run = computeFinalRanking(
        ctx: ctx,
        tiers: tiers,
        koRankCount: 16,
        pMin: 5,
      );

      SkvPlacement byId(List<SkvPlacement> r, String id) =>
          r.firstWhere((p) => p.participantId == id);

      expect(
        byId(defaultRun, 'T').points,
        skvPointsForPlacement(ctx: ctx, placement: 20, koRankCount: 16),
      );
      expect(
        byId(pMin5Run, 'T').points,
        skvPointsForPlacement(
          ctx: ctx,
          placement: 20,
          koRankCount: 16,
          pMin: 5,
        ),
      );
      // pMin 5 must not undercut pMin 3 at the last place.
      expect(
        byId(pMin5Run, 'T').points,
        greaterThanOrEqualTo(byId(defaultRun, 'T').points),
      );
    });

    test('minimal valid field (N == koRankCount, no tail) runs cleanly', () {
      // N = koRankCount = 4, ranks 1..4 as singleton tiers.
      const ctx = SkvTournamentContext(fieldSize: 4, league: SkvLeague.a);
      final result = computeFinalRanking(
        ctx: ctx,
        tiers: const <List<String>>[
          <String>['A'],
          <String>['B'],
          <String>['C'],
          <String>['D'],
        ],
        koRankCount: 4,
      );
      expect(result.map((p) => p.rank).toList(), <int>[1, 2, 3, 4]);
      // W for N=4, league A: 100 * (1 + (4-10)/20) = 70.
      expect(result[0].points, 70);
      expect(result[1].points, 56); // 0.8 * 70
      expect(result[2].points, 46); // 0.65 * 70 = 45.5 -> 46
      expect(result[3].points, 35); // 0.5 * 70
    });
  });

  group('computeFinalRanking validation', () {
    const ctx = SkvTournamentContext(fieldSize: 16, league: SkvLeague.a);

    test('tier sum < N throws ArgumentError', () {
      expect(
        () => computeFinalRanking(
          ctx: ctx,
          tiers: const <List<String>>[
            <String>['A'],
            <String>['B'],
          ],
          koRankCount: 16,
        ),
        throwsArgumentError,
      );
    });

    test('tier sum > N throws ArgumentError', () {
      const ctxSmall = SkvTournamentContext(fieldSize: 4, league: SkvLeague.a);
      expect(
        () => computeFinalRanking(
          ctx: ctxSmall,
          tiers: const <List<String>>[
            <String>['A'],
            <String>['B'],
            <String>['C'],
            <String>['D'],
            <String>['E'],
          ],
          koRankCount: 4,
        ),
        throwsArgumentError,
      );
    });

    test('duplicate participantId across tiers throws ArgumentError', () {
      const ctxSmall = SkvTournamentContext(fieldSize: 4, league: SkvLeague.a);
      expect(
        () => computeFinalRanking(
          ctx: ctxSmall,
          tiers: const <List<String>>[
            <String>['A'],
            <String>['B'],
            <String>['A'],
            <String>['D'],
          ],
          koRankCount: 4,
        ),
        throwsArgumentError,
      );
    });

    test('empty tier in an otherwise valid list throws ArgumentError', () {
      const ctxSmall = SkvTournamentContext(fieldSize: 4, league: SkvLeague.a);
      expect(
        () => computeFinalRanking(
          ctx: ctxSmall,
          tiers: const <List<String>>[
            <String>['A'],
            <String>[],
            <String>['B'],
            <String>['C'],
            <String>['D'],
          ],
          koRankCount: 4,
        ),
        throwsArgumentError,
      );
    });

    test('empty tiers list throws ArgumentError', () {
      expect(
        () => computeFinalRanking(
          ctx: ctx,
          tiers: const <List<String>>[],
          koRankCount: 16,
        ),
        throwsArgumentError,
      );
    });
  });

  group('skvLeagueFromTournament', () {
    test('teamSize 1 -> einzel regardless of categories', () {
      expect(
        skvLeagueFromTournament(teamSize: 1, leagueCategories: <String>{}),
        SkvLeague.einzel,
      );
      expect(
        skvLeagueFromTournament(
          teamSize: 1,
          leagueCategories: <String>{'A', 'B', 'C'},
        ),
        SkvLeague.einzel,
      );
    });

    test("{'C'} with teamSize > 1 -> c", () {
      expect(
        skvLeagueFromTournament(teamSize: 2, leagueCategories: <String>{'C'}),
        SkvLeague.c,
      );
    });

    test("{'A'} and {'A','B'} -> a", () {
      expect(
        skvLeagueFromTournament(teamSize: 2, leagueCategories: <String>{'A'}),
        SkvLeague.a,
      );
      expect(
        skvLeagueFromTournament(
          teamSize: 2,
          leagueCategories: <String>{'A', 'B'},
        ),
        SkvLeague.a,
      );
    });

    test("{'A','C'} -> a (A present beats C-only rule)", () {
      expect(
        skvLeagueFromTournament(
          teamSize: 2,
          leagueCategories: <String>{'A', 'C'},
        ),
        SkvLeague.a,
      );
    });

    test('empty set with teamSize > 1 -> a', () {
      expect(
        skvLeagueFromTournament(teamSize: 2, leagueCategories: <String>{}),
        SkvLeague.a,
      );
    });

    test('case-insensitive: {c} -> c, {a} -> a', () {
      expect(
        skvLeagueFromTournament(teamSize: 2, leagueCategories: <String>{'c'}),
        SkvLeague.c,
      );
      expect(
        skvLeagueFromTournament(teamSize: 2, leagueCategories: <String>{'a'}),
        SkvLeague.a,
      );
    });

    test('determinism: same input -> same result', () {
      final a = skvLeagueFromTournament(
        teamSize: 2,
        leagueCategories: <String>{'B', 'C'},
      );
      final b = skvLeagueFromTournament(
        teamSize: 2,
        leagueCategories: <String>{'B', 'C'},
      );
      expect(a, b);
    });
  });
}
