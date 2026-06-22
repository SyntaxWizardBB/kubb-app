import 'package:kubb_domain/src/tournament/pairing.dart';
import 'package:test/test.dart';

import '../golden/sm_einzel_2026_fixture.dart';

void main() {
  group('SwissSystemStrategy.planRound', () {
    const strategy = SwissSystemStrategy();

    test('8 players, no completed matches → 4 unique pairings', () {
      final players = List<String>.generate(8, (i) => 'P${i + 1}');
      final round = strategy.planRound(
        participants: players,
        completedMatches: const [],
        roundNumber: 1,
        tournamentId: 't1',
      );

      expect(round.roundNumber, equals(1));
      expect(round.pairings, hasLength(4));
      final seen = <String>{};
      for (final p in round.pairings) {
        expect(p.isBye, isFalse);
        seen
          ..add(p.participantA)
          ..add(p.participantB!);
      }
      expect(seen.length, equals(8));
    });

    test('7 players → exactly one bye in round 1', () {
      final players = List<String>.generate(7, (i) => 'P${i + 1}');
      final round = strategy.planRound(
        participants: players,
        completedMatches: const [],
        roundNumber: 1,
        tournamentId: 't1',
      );

      final byes = round.pairings.where((p) => p.isBye).toList();
      expect(byes, hasLength(1));
      expect(round.pairings.where((p) => !p.isBye), hasLength(3));
    });

    test('round 2 avoids round 1 pairings when possible', () {
      final players = List<String>.generate(8, (i) => 'P${i + 1}');
      final r1 = strategy.planRound(
        participants: players,
        completedMatches: const [],
        roundNumber: 1,
        tournamentId: 't1',
      );

      final round1Matches = <MatchResult>[
        for (final p in r1.pairings)
          if (!p.isBye)
            MatchResult(
              participantA: p.participantA,
              participantB: p.participantB,
              pointsA: 3,
              pointsB: 0,
              roundNumber: 1,
            ),
      ];

      final r2 = strategy.planRound(
        participants: players,
        completedMatches: round1Matches,
        roundNumber: 2,
        tournamentId: 't1',
      );

      final round1Keys = <String>{
        for (final p in r1.pairings)
          if (!p.isBye)
            _key(p.participantA, p.participantB!),
      };
      for (final p in r2.pairings) {
        if (p.isBye) continue;
        expect(round1Keys, isNot(contains(_key(p.participantA, p.participantB!))));
      }
    });

    test('two runs with identical inputs produce identical pairings', () {
      final players = List<String>.generate(8, (i) => 'P${i + 1}');
      const matches = <MatchResult>[
        MatchResult(participantA: 'P1', participantB: 'P2', pointsA: 16, pointsB: 5, roundNumber: 1),
        MatchResult(participantA: 'P3', participantB: 'P4', pointsA: 12, pointsB: 11, roundNumber: 1),
        MatchResult(participantA: 'P5', participantB: 'P6', pointsA: 9, pointsB: 9, roundNumber: 1),
        MatchResult(participantA: 'P7', participantB: 'P8', pointsA: 16, pointsB: 2, roundNumber: 1),
      ];
      final a = strategy.planRound(
        participants: players,
        completedMatches: matches,
        roundNumber: 2,
        tournamentId: 't1',
      );
      final b = strategy.planRound(
        participants: players,
        completedMatches: matches,
        roundNumber: 2,
        tournamentId: 't1',
      );
      expect(a.pairings, equals(b.pairings));
    });

    // When points, Buchholz and head-to-head all tie, the only thing left to
    // order players by is the stable start number. Spec §6.1 fixes that as the
    // input order (ascending), so eight fresh players must pair adjacently:
    // P1-P2, P3-P4, P5-P6, P7-P8. The old RNG jitter tiebreak shuffled this
    // into a hash-derived order, so this assertion is red against it.
    test('all-tie round 1 pairs adjacently by start number, no hash jitter', () {
      final players = List<String>.generate(8, (i) => 'P${i + 1}');
      final round = strategy.planRound(
        participants: players,
        completedMatches: const [],
        roundNumber: 1,
        tournamentId: 't1',
      );

      expect(
        round.pairings,
        equals(const [
          PlannedPairing(participantA: 'P1', participantB: 'P2'),
          PlannedPairing(participantA: 'P3', participantB: 'P4'),
          PlannedPairing(participantA: 'P5', participantB: 'P6'),
          PlannedPairing(participantA: 'P7', participantB: 'P8'),
        ]),
      );
    });

    // The tiebreak must not depend on String.hashCode or a per-round RNG:
    // two rosters that differ only in their tournamentId must, on an all-tie
    // round, yield the same start-number-ordered pairing. RNG jitter seeded
    // from tournamentId.hashCode breaks this.
    test('tiebreak is independent of tournamentId hash', () {
      final players = List<String>.generate(8, (i) => 'P${i + 1}');
      final a = strategy.planRound(
        participants: players,
        completedMatches: const [],
        roundNumber: 1,
        tournamentId: 'tournament-alpha',
      );
      final b = strategy.planRound(
        participants: players,
        completedMatches: const [],
        roundNumber: 1,
        tournamentId: 'a-very-different-id-with-other-hash',
      );
      expect(a.pairings, equals(b.pairings));
    });

    test('bye prediction matches SM Einzel 2026 for rounds 2-8', () {
      // Spec §7.3: weakest player without a prior bye. Round 1 has no
      // standings to rank by, so it is excluded; rounds 2-8 are reconstructed
      // from the real prior results and must hit 7/7.
      const expectedByes = <int, String>{
        2: 'Börny',
        3: 'Laura',
        4: 'Schibu',
        5: 'Meff',
        6: 'Tom Kreuzfahrt',
        7: 'Kubbacca',
        8: 'LaMartina',
      };
      for (final round in expectedByes.keys) {
        final prior = [
          for (final m in smEinzel2026Matches)
            if (m.roundNumber < round) m,
        ];
        final planned = strategy.planRound(
          participants: smEinzel2026Participants,
          completedMatches: prior,
          roundNumber: round,
          tournamentId: 'sm-einzel-2026',
        );
        final byes = planned.pairings.where((p) => p.isBye).toList();
        expect(byes, hasLength(1), reason: 'round $round must have one bye');
        expect(
          byes.single.participantA,
          equals(expectedByes[round]),
          reason: 'round $round bye player',
        );
      }
    });
  });
}

String _key(String a, String b) =>
    a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
