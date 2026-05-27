import 'package:kubb_domain/src/tournament/ekc_score.dart';
import 'package:kubb_domain/src/tournament/pairing.dart';
import 'package:kubb_domain/src/tournament/pairing/swiss_system.dart';
import 'package:kubb_domain/src/tournament/standings.dart';
import 'package:test/test.dart';

List<String> _ids(int n) => List.generate(n, (i) => 'P${i + 1}');

MatchEkcScore _winA() => MatchEkcScore([
      SetScore(
        basekubbsKnockedByA: 6,
        basekubbsKnockedByB: 2,
        winner: SetWinner.teamA,
      ),
      SetScore(
        basekubbsKnockedByA: 6,
        basekubbsKnockedByB: 3,
        winner: SetWinner.teamA,
      ),
    ]);

MatchEkcScore _emptyScore() => MatchEkcScore(const []);

TournamentMatchResult _match(String a, String b) => TournamentMatchResult(
      participantA: a,
      participantB: b,
      score: _winA(),
    );

TournamentMatchResult _bye(String a) => TournamentMatchResult(
      participantA: a,
      participantB: null,
      score: _emptyScore(),
    );

Set<Set<String>> _pairingSet(List<PlannedPairing> ps) => {
      for (final p in ps)
        if (!p.isBye) {p.participantA, p.participantB!},
    };

void main() {
  group('SwissSystemStrategy', () {
    test('8 Spieler, 0 Runden -> 4 Pairings, keine Wiederholung, Bye-Liste leer',
        () {
      final strategy = SwissSystemStrategy(tournamentId: 't-8');
      final result = strategy.planNextRound(
        participantIds: _ids(8),
        priorResults: const [],
        nextRoundNumber: 1,
      );

      expect(result.pairings, hasLength(4));
      expect(result.pairings.any((p) => p.isBye), isFalse);
      expect(result.byeParticipantId, isNull);
      expect(result.repeated, isFalse);
      // Alle 8 Spieler genau einmal eingeplant.
      final allParticipants = <String>{
        for (final p in result.pairings) ...[p.participantA, p.participantB!],
      };
      expect(allParticipants, hasLength(8));
    });

    test(
        '7 Spieler ungerade -> genau 1 Bye-Slot, schwaechster ohne Bye-Vorgeschichte',
        () {
      final strategy = SwissSystemStrategy(tournamentId: 't-7');
      // Round-1-Vorgeschichte: P1>P2, P3>P4, P5>P6, P7 hatte Bye in R1.
      // Nach R1 sind P1,P3,P5 stark (Sieger), P7 mittel (Bye), P2,P4,P6 schwach.
      // In R2 darf NUR ein Spieler ohne Bye-Vorgeschichte den Bye bekommen,
      // also einer aus {P2, P4, P6} - NICHT P7 (FR-PAIR-5).
      final prior = <TournamentMatchResult>[
        _match('P1', 'P2'),
        _match('P3', 'P4'),
        _match('P5', 'P6'),
        _bye('P7'),
      ];

      final result = strategy.planNextRound(
        participantIds: _ids(7),
        priorResults: prior,
        nextRoundNumber: 2,
      );

      // 7 Spieler -> 3 regulaere Pairings + 1 Bye-Slot.
      expect(result.pairings.where((p) => p.isBye), hasLength(1));
      expect(result.byeParticipantId, isNotNull);
      expect(
        result.byeParticipantId,
        isNot('P7'),
        reason: 'P7 hatte bereits einen Bye in R1',
      );
      expect(
        {'P2', 'P4', 'P6'},
        contains(result.byeParticipantId),
        reason: 'schwaechster Spieler ohne Bye-Vorgeschichte bekommt den Bye',
      );
    });

    test(
        '8 Spieler nach 3 Runden -> Permutation der Eingabereihenfolge ergibt gleiches Pairing-Set',
        () {
      final ids = _ids(8);
      // 3 Runden Vorgeschichte (kreuz-Paarungen, keine Wiederholung).
      final prior = <TournamentMatchResult>[
        // R1
        _match('P1', 'P8'),
        _match('P2', 'P7'),
        _match('P3', 'P6'),
        _match('P4', 'P5'),
        // R2
        _match('P1', 'P7'),
        _match('P8', 'P6'),
        _match('P2', 'P5'),
        _match('P3', 'P4'),
        // R3
        _match('P1', 'P6'),
        _match('P7', 'P5'),
        _match('P8', 'P4'),
        _match('P2', 'P3'),
      ];

      final stratA = SwissSystemStrategy(tournamentId: 't-perm', roundSeed: 4);
      final stratB = SwissSystemStrategy(tournamentId: 't-perm', roundSeed: 4);

      final r1 = stratA.planNextRound(
        participantIds: ids,
        priorResults: prior,
        nextRoundNumber: 4,
      );
      // Permutierte Input-Liste -> Pairings muessen mengen-identisch sein.
      final reversed = ids.reversed.toList();
      final r2 = stratB.planNextRound(
        participantIds: reversed,
        priorResults: prior,
        nextRoundNumber: 4,
      );

      expect(_pairingSet(r2.pairings), equals(_pairingSet(r1.pairings)));

      // Keine Wiederholung gegenueber den 3 vorhergehenden Runden.
      final priorPairs = <Set<String>>{
        for (final m in prior)
          if (m.participantB != null) {m.participantA, m.participantB!},
      };
      for (final p in r1.pairings) {
        if (p.isBye) continue;
        expect(
          priorPairs.contains({p.participantA, p.participantB!}),
          isFalse,
          reason:
              'Pairing ${p.participantA}-${p.participantB} wiederholt sich gegenueber prior',
        );
      }
    });

    test('Tiebreak Buchholz -> Direct-Encounter -> Random(seed) ist deterministisch',
        () {
      // OD-M5-01 Empfehlung B: bei punktgleichen Spielern entscheidet
      // Buchholz, dann Direct-Encounter, dann Random(seed) -
      // Random-Seed = tournament_id + round_no.
      final ids = _ids(8);
      final prior = <TournamentMatchResult>[
        _match('P1', 'P2'),
        _match('P3', 'P4'),
        _match('P5', 'P6'),
        _match('P7', 'P8'),
      ];

      // Gleicher Seed -> identische Ausgabe.
      final s1 = SwissSystemStrategy(tournamentId: 't-tb', roundSeed: 2);
      final s2 = SwissSystemStrategy(tournamentId: 't-tb', roundSeed: 2);
      final a = s1.planNextRound(
        participantIds: ids,
        priorResults: prior,
        nextRoundNumber: 2,
      );
      final b = s2.planNextRound(
        participantIds: ids,
        priorResults: prior,
        nextRoundNumber: 2,
      );
      expect(_pairingSet(b.pairings), equals(_pairingSet(a.pairings)));

      // Anderer Seed -> deterministisch reproduzierbar bei wiederholtem Aufruf.
      final s3 = SwissSystemStrategy(tournamentId: 't-tb', roundSeed: 99);
      final c1 = s3.planNextRound(
        participantIds: ids,
        priorResults: prior,
        nextRoundNumber: 2,
      );
      final c2 = s3.planNextRound(
        participantIds: ids,
        priorResults: prior,
        nextRoundNumber: 2,
      );
      expect(_pairingSet(c2.pairings), equals(_pairingSet(c1.pairings)));
    });
  });
}
