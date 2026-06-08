// M2a: executable spec for the canonical, phase-/scoring-dependent set
// winner derivation that makes "same reality == consensus agreement" hold.
import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('resolveSetWinnerForSide', () {
    test('king fell on A -> A wins (any phase / scoring)', () {
      for (final phase in MatchPhase.values) {
        for (final scoring in SetScoring.values) {
          expect(
            resolveSetWinnerForSide(
              kingSide: SetWinner.teamA,
              basekubbsA: 0,
              basekubbsB: 5,
              phase: phase,
              scoring: scoring,
            ),
            SetWinner.teamA,
            reason: 'king side must win regardless of kubbs/$phase/$scoring',
          );
        }
      }
    });

    test('king fell on B -> B wins even with fewer kubbs', () {
      expect(
        resolveSetWinnerForSide(
          kingSide: SetWinner.teamB,
          basekubbsA: 5,
          basekubbsB: 1,
          phase: MatchPhase.group,
          scoring: SetScoring.ekc,
        ),
        SetWinner.teamB,
      );
    });

    test('group + classic + no king -> none (no forced winner)', () {
      // The root-cause case: previously kubbsA >= kubbsB forced A.
      expect(
        resolveSetWinnerForSide(
          kingSide: null,
          basekubbsA: 5,
          basekubbsB: 1,
          phase: MatchPhase.group,
          scoring: SetScoring.classic,
        ),
        SetWinner.none,
      );
      // Even an exact draw is none, never an auto winner.
      expect(
        resolveSetWinnerForSide(
          kingSide: null,
          basekubbsA: 3,
          basekubbsB: 3,
          phase: MatchPhase.group,
          scoring: SetScoring.classic,
        ),
        SetWinner.none,
      );
    });

    test('group + EKC + no king -> winner by kubbs, draw allowed', () {
      expect(
        resolveSetWinnerForSide(
          kingSide: null,
          basekubbsA: 5,
          basekubbsB: 2,
          phase: MatchPhase.group,
          scoring: SetScoring.ekc,
        ),
        SetWinner.teamA,
      );
      expect(
        resolveSetWinnerForSide(
          kingSide: null,
          basekubbsA: 2,
          basekubbsB: 5,
          phase: MatchPhase.group,
          scoring: SetScoring.ekc,
        ),
        SetWinner.teamB,
      );
      expect(
        resolveSetWinnerForSide(
          kingSide: null,
          basekubbsA: 4,
          basekubbsB: 4,
          phase: MatchPhase.group,
          scoring: SetScoring.ekc,
        ),
        SetWinner.none,
        reason: 'equal kubbs in EKC group is a draw (none)',
      );
    });

    test('KO + no king -> none (no auto kubb-majority fallback; M2b owns it)',
        () {
      for (final scoring in SetScoring.values) {
        expect(
          resolveSetWinnerForSide(
            kingSide: null,
            basekubbsA: 5,
            basekubbsB: 0,
            phase: MatchPhase.ko,
            scoring: scoring,
          ),
          SetWinner.none,
          reason: 'KO king-less set must NOT fabricate a winner here',
        );
      }
    });

    test('two identical king-less group/classic inputs agree (no dispute)', () {
      SetWinner derive() => resolveSetWinnerForSide(
            kingSide: null,
            basekubbsA: 3,
            basekubbsB: 2,
            phase: MatchPhase.group,
            scoring: SetScoring.classic,
          );
      expect(derive(), derive());
      expect(derive(), SetWinner.none);
    });
  });

  group('resolveSetWinner (KingOutcome-based)', () {
    test('no king + group + classic -> none', () {
      expect(
        resolveSetWinner(
          kingOutcome: const KingMissed(),
          basekubbsA: 5,
          basekubbsB: 0,
          phase: MatchPhase.group,
          scoring: SetScoring.classic,
        ),
        SetWinner.none,
      );
    });

    test('timed-out king + group + EKC -> by kubbs', () {
      expect(
        resolveSetWinner(
          kingOutcome: const KingTimedOut(),
          basekubbsA: 1,
          basekubbsB: 4,
          phase: MatchPhase.group,
          scoring: SetScoring.ekc,
        ),
        SetWinner.teamB,
      );
    });
  });

  group('matchPhaseFromWire', () {
    test('group token -> group; bracket tokens / null -> ko / group', () {
      expect(matchPhaseFromWire('group'), MatchPhase.group);
      expect(matchPhaseFromWire(null), MatchPhase.group);
      for (final ko in <String>[
        'ko',
        'final',
        'third_place',
        'wb',
        'lb',
        'grand_final',
        'grand_final_reset',
        'consolation',
        'consolation_third_place',
      ]) {
        expect(matchPhaseFromWire(ko), MatchPhase.ko, reason: '$ko is KO');
      }
    });
  });

  group('MatchEkcScore does not count a none set as a win', () {
    test('none set adds no set-win and no winner bonus to either side', () {
      final ekc = computeEkc(<SetScore>[
        SetScore(
          basekubbsKnockedByA: 3,
          basekubbsKnockedByB: 3,
          winner: SetWinner.none,
        ),
      ]);
      expect(ekc.setsWonA, 0);
      expect(ekc.setsWonB, 0);
      expect(ekc.matchWinner, isNull);
      // Base kubbs still tally; no +3 winner bonus on a none set.
      expect(ekc.pointsForA, 3);
      expect(ekc.pointsForB, 3);
    });
  });
}
