import 'package:kubb_domain/src/tournament/skv_tour_points.dart';
import 'package:test/test.dart';

/// Builds a normal (non-Masters) context.
SkvTournamentContext _ctx(int n, SkvLeague league) =>
    SkvTournamentContext(fieldSize: n, league: league);

/// Convenience for [skvPointsForPlacement] over a range of ranks.
List<int> _ranks(
  SkvTournamentContext ctx,
  int koRankCount,
  Iterable<int> ranks, {
  int pMin = 3,
}) => [
  for (final r in ranks)
    skvPointsForPlacement(
      ctx: ctx,
      placement: r,
      koRankCount: koRankCount,
      pMin: pMin,
    ),
];

void main() {
  group('skvWinnerPoints', () {
    test('league A scales linearly with field size (B = 10)', () {
      expect(skvWinnerPoints(_ctx(42, SkvLeague.a)), 260);
      expect(skvWinnerPoints(_ctx(28, SkvLeague.a)), 190);
      expect(skvWinnerPoints(_ctx(16, SkvLeague.a)), 130);
      expect(skvWinnerPoints(_ctx(10, SkvLeague.a)), 100);
    });

    test('league B uses the same reference size as A (B = 10)', () {
      expect(skvWinnerPoints(_ctx(10, SkvLeague.b)), 100);
      expect(skvWinnerPoints(_ctx(16, SkvLeague.b)), 130);
    });

    test('league C uses B = 20', () {
      expect(skvWinnerPoints(_ctx(20, SkvLeague.c)), 100);
    });

    test('einzel uses B = 40 and rounds half away from zero', () {
      // round(100 * (1 + (73 - 40) / 80)) = round(141.25) = 141.
      expect(skvWinnerPoints(_ctx(73, SkvLeague.einzel)), 141);
    });

    test('Masters points are fixed, not field-scaled', () {
      // A/C -> x2, B -> x1; field size must not influence the result.
      expect(
        skvWinnerPoints(
          const SkvTournamentContext(
            fieldSize: 8,
            league: SkvLeague.a,
            isMasters: true,
          ),
        ),
        200,
      );
      expect(
        skvWinnerPoints(
          const SkvTournamentContext(
            fieldSize: 99,
            league: SkvLeague.b,
            isMasters: true,
          ),
        ),
        100,
      );
      expect(
        skvWinnerPoints(
          const SkvTournamentContext(
            fieldSize: 16,
            league: SkvLeague.c,
            isMasters: true,
          ),
        ),
        200,
      );
    });
  });

  group('skvPointsForPlacement ranks 1-4', () {
    test('league A, N=16: fixed factors [1.0, 0.8, 0.65, 0.5]', () {
      final ctx = _ctx(16, SkvLeague.a);
      expect(_ranks(ctx, 16, [1, 2, 3, 4]), [130, 104, 85, 65]);
    });

    test('league A, N=42, koRankCount=32: top ranks', () {
      final ctx = _ctx(42, SkvLeague.a);
      expect(_ranks(ctx, 32, [1, 2, 3, 4]), [260, 208, 169, 130]);
    });
  });

  group('KO tiers', () {
    test('league A, N=16, koRankCount=16: tier 1 (5-8) and tier 2 (9-16)', () {
      final ctx = _ctx(16, SkvLeague.a);
      // Tier 1: round(130 * 0.25) = 33 for each of ranks 5..8.
      for (final r in [5, 6, 7, 8]) {
        expect(
          skvPointsForPlacement(ctx: ctx, placement: r, koRankCount: 16),
          33,
          reason: 'rank $r should be tier 1',
        );
      }
      // Tier 2: round(130 * 0.125) = 16 for each of ranks 9..16.
      for (var r = 9; r <= 16; r++) {
        expect(
          skvPointsForPlacement(ctx: ctx, placement: r, koRankCount: 16),
          16,
          reason: 'rank $r should be tier 2',
        );
      }
    });

    test('tier 3 (ranks 17-32) = 0.0625 * W', () {
      // N=32 league A: W = 100 * (1 + 22/20) = 210.
      final ctx = _ctx(32, SkvLeague.a);
      expect(skvWinnerPoints(ctx), 210);
      // round(210 * 0.0625) = round(13.125) = 13.
      for (final r in [17, 24, 32]) {
        expect(
          skvPointsForPlacement(ctx: ctx, placement: r, koRankCount: 32),
          13,
          reason: 'rank $r should be tier 3',
        );
      }
    });
  });

  group('Vorrunden-Schwanz', () {
    test('league A, N=42, koRankCount=32: tail r33..r42 decays to pMin', () {
      final ctx = _ctx(42, SkvLeague.a);
      final tail = _ranks(ctx, 32, [33, 34, 35, 36, 37, 38, 39, 40, 41, 42]);
      expect(tail, [15, 13, 12, 11, 10, 8, 7, 6, 4, 3]);
    });

    test('tail is monotonically non-increasing and starts below P_last', () {
      final ctx = _ctx(42, SkvLeague.a);
      // P_last == KO value at the last KO rank (32).
      final pLast = skvPointsForPlacement(
        ctx: ctx,
        placement: 32,
        koRankCount: 32,
      );
      expect(pLast, 16);
      final tail = _ranks(ctx, 32, [for (var r = 33; r <= 42; r++) r]);
      for (var i = 1; i < tail.length; i++) {
        expect(tail[i] <= tail[i - 1], isTrue, reason: 'index $i not falling');
      }
      // Last rank reaches exactly pMin (default 3).
      expect(tail.last, 3);
      expect(tail.first <= pLast, isTrue);
    });

    test('pMin parametrisation: last rank reaches the configured pMin', () {
      final ctx = _ctx(42, SkvLeague.a);
      final tail = _ranks(
        ctx,
        32,
        [for (var r = 33; r <= 42; r++) r],
        pMin: 5,
      );
      expect(tail.last, 5);
      for (var i = 1; i < tail.length; i++) {
        expect(tail[i] <= tail[i - 1], isTrue);
      }
    });
  });

  group('edge cases & validation', () {
    test('koRankCount == N: no tail, last rank is the KO-tier value', () {
      final ctx = _ctx(16, SkvLeague.a);
      // Rank 16 with koRankCount == 16 must not enter the tail branch
      // (which would divide by M = 0); it is the tier-2 value 16.
      expect(
        skvPointsForPlacement(ctx: ctx, placement: 16, koRankCount: 16),
        16,
      );
    });

    test('koRankCount == 4 (minimum): ranks 5..N are entirely tail', () {
      // N=8 league A: W = 90. P_last = KO-tier value at rank 4
      // (tier formula) = round(90 * 0.25) = 23. Tail r5..r8 = [18,13,8,3].
      final ctx = _ctx(8, SkvLeague.a);
      expect(skvWinnerPoints(ctx), 90);
      final tail = _ranks(ctx, 4, [5, 6, 7, 8]);
      expect(tail, [18, 13, 8, 3]);
      for (var i = 1; i < tail.length; i++) {
        expect(tail[i] <= tail[i - 1], isTrue);
      }
      expect(tail.last, 3);
    });

    test('placement out of range throws ArgumentError', () {
      final ctx = _ctx(16, SkvLeague.a);
      expect(
        () => skvPointsForPlacement(ctx: ctx, placement: 0, koRankCount: 16),
        throwsArgumentError,
      );
      expect(
        () => skvPointsForPlacement(ctx: ctx, placement: 17, koRankCount: 16),
        throwsArgumentError,
      );
    });

    test('koRankCount out of range throws ArgumentError', () {
      final ctx = _ctx(16, SkvLeague.a);
      expect(
        () => skvPointsForPlacement(ctx: ctx, placement: 1, koRankCount: 3),
        throwsArgumentError,
      );
      expect(
        () => skvPointsForPlacement(ctx: ctx, placement: 1, koRankCount: 17),
        throwsArgumentError,
      );
    });

    test('fieldSize < 1 throws ArgumentError in both functions', () {
      const ctx = SkvTournamentContext(fieldSize: 0, league: SkvLeague.a);
      expect(() => skvWinnerPoints(ctx), throwsArgumentError);
      expect(
        () => skvPointsForPlacement(ctx: ctx, placement: 1, koRankCount: 4),
        throwsArgumentError,
      );
    });
  });

  group('determinism', () {
    test('identical inputs yield identical outputs', () {
      final ctx = _ctx(42, SkvLeague.a);
      final first = _ranks(ctx, 32, [for (var r = 1; r <= 42; r++) r]);
      final second = _ranks(ctx, 32, [for (var r = 1; r <= 42; r++) r]);
      expect(first, second);

      expect(
        skvWinnerPoints(_ctx(73, SkvLeague.einzel)),
        skvWinnerPoints(_ctx(73, SkvLeague.einzel)),
      );
    });
  });
}
