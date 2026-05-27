import 'package:kubb_domain/src/tournament/pairing.dart';
import 'package:kubb_domain/src/tournament/pairing/buchholz.dart';
import 'package:kubb_domain/src/tournament/pairing/swiss_system.dart';
import 'package:test/test.dart';

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

    test('same seed yields deterministic pairings', () {
      final players = List<String>.generate(8, (i) => 'P${i + 1}');
      final a = strategy.planRound(
        participants: players,
        completedMatches: const [],
        roundNumber: 1,
        tournamentId: 't1',
      );
      final b = strategy.planRound(
        participants: players,
        completedMatches: const [],
        roundNumber: 1,
        tournamentId: 't1',
      );
      expect(a.pairings, equals(b.pairings));
    });
  });
}

String _key(String a, String b) =>
    a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
