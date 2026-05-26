// Tests pass explicit `null` for empty slots so the intent of each row is
// obvious — accept the redundant-arg lint for clarity.
// ignore_for_file: avoid_redundant_argument_values

import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

KoMatchRow _row({
  required int roundNumber,
  required int bracketPosition,
  BracketPhase phase = BracketPhase.winners,
  String? participantA,
  String? participantB,
  String? winnerParticipantId,
  bool isBye = false,
}) =>
    (
      roundNumber: roundNumber,
      bracketPosition: bracketPosition,
      phase: phase,
      participantA: participantA,
      participantB: participantB,
      winnerParticipantId: winnerParticipantId,
      isBye: isBye,
    );

void main() {
  group('bracketFromMatches', () {
    test('it throws on empty input', () {
      expect(() => bracketFromMatches(const []), throwsArgumentError);
    });

    test('it rebuilds a 7-match bracket for 8 participants', () {
      // Round 1: 4 matches, all participants known.
      // Round 2: 2 matches, only winners of QF1+QF2 known so far.
      // Round 3 (final): empty slots.
      final matches = <KoMatchRow>[
        _row(roundNumber: 1, bracketPosition: 1,
            participantA: 'p1', participantB: 'p8',
            winnerParticipantId: 'p1'),
        _row(roundNumber: 1, bracketPosition: 2,
            participantA: 'p4', participantB: 'p5',
            winnerParticipantId: 'p4'),
        _row(roundNumber: 1, bracketPosition: 3,
            participantA: 'p3', participantB: 'p6'),
        _row(roundNumber: 1, bracketPosition: 4,
            participantA: 'p2', participantB: 'p7'),
        _row(roundNumber: 2, bracketPosition: 1,
            participantA: 'p1', participantB: 'p4'),
        _row(roundNumber: 2, bracketPosition: 2,
            participantA: null, participantB: null),
        _row(roundNumber: 3, bracketPosition: 1,
            phase: BracketPhase.finals,
            participantA: null, participantB: null),
      ];

      final bracket =
          bracketFromMatches(matches) as SingleEliminationBracket;
      expect(bracket.rounds, hasLength(3));
      expect(bracket.rounds[0].pairings, hasLength(4));
      expect(bracket.rounds[1].pairings, hasLength(2));
      expect(bracket.rounds[2].pairings, hasLength(1));
      // Final round carries the `finals` phase marker.
      expect(bracket.rounds[2].phase, BracketPhase.finals);
      // Filled vs. empty slot reflects DB state, not derived from winners.
      expect(bracket.rounds[0].pairings[0].$1.participantId, 'p1');
      expect(bracket.rounds[0].pairings[0].$2.participantId, 'p8');
      expect(bracket.rounds[1].pairings[1].$1.participantId, isNull);
      expect(bracket.rounds[2].pairings[0].$2.participantId, isNull);
    });

    test('it stays passive — winner does not auto-fill the next slot', () {
      // QF1 has a winner, but SF1's slot is still empty in the DB.
      // bracketFromMatches must NOT promote the winner; the trigger does.
      final matches = <KoMatchRow>[
        _row(roundNumber: 1, bracketPosition: 1,
            participantA: 'p1', participantB: 'p8',
            winnerParticipantId: 'p1'),
        _row(roundNumber: 1, bracketPosition: 2,
            participantA: 'p4', participantB: 'p5'),
        _row(roundNumber: 2, bracketPosition: 1,
            participantA: null, participantB: null),
      ];

      final bracket =
          bracketFromMatches(matches) as SingleEliminationBracket;
      expect(bracket.rounds[1].pairings.single.$1.participantId, isNull);
      expect(bracket.rounds[1].pairings.single.$2.participantId, isNull);
    });

    test('it places a third-place row in a dedicated round', () {
      final matches = <KoMatchRow>[
        _row(roundNumber: 1, bracketPosition: 1,
            participantA: 'p1', participantB: 'p4'),
        _row(roundNumber: 1, bracketPosition: 2,
            participantA: 'p2', participantB: 'p3'),
        _row(roundNumber: 2, bracketPosition: 1,
            phase: BracketPhase.finals,
            participantA: null, participantB: null),
        _row(roundNumber: 2, bracketPosition: 1,
            phase: BracketPhase.thirdPlace,
            participantA: null, participantB: null),
      ];

      final bracket =
          bracketFromMatches(matches) as SingleEliminationBracket;
      // 2 winners-side rounds + 1 third-place round.
      expect(bracket.rounds, hasLength(3));
      final thirdPlace =
          bracket.rounds.where((r) => r.phase == BracketPhase.thirdPlace);
      expect(thirdPlace, hasLength(1));
      expect(thirdPlace.single.pairings, hasLength(1));
    });

    test('it carries a BYE slot through to the bracket', () {
      final matches = <KoMatchRow>[
        _row(roundNumber: 1, bracketPosition: 1,
            participantA: 'p1', participantB: null, isBye: true),
        _row(roundNumber: 1, bracketPosition: 2,
            participantA: 'p2', participantB: 'p3'),
        _row(roundNumber: 2, bracketPosition: 1,
            participantA: null, participantB: null),
      ];

      final bracket =
          bracketFromMatches(matches) as SingleEliminationBracket;
      expect(bracket.rounds[0].pairings[0].$1.isBye, isTrue);
      expect(bracket.rounds[0].pairings[0].$2.isBye, isTrue);
      expect(bracket.rounds[0].pairings[0].$1.participantId, 'p1');
    });

    test('it sorts pairings by bracket_position regardless of input order', () {
      final matches = <KoMatchRow>[
        _row(roundNumber: 1, bracketPosition: 3,
            participantA: 'p3', participantB: 'p6'),
        _row(roundNumber: 1, bracketPosition: 1,
            participantA: 'p1', participantB: 'p8'),
        _row(roundNumber: 1, bracketPosition: 4,
            participantA: 'p2', participantB: 'p7'),
        _row(roundNumber: 1, bracketPosition: 2,
            participantA: 'p4', participantB: 'p5'),
      ];

      final bracket =
          bracketFromMatches(matches) as SingleEliminationBracket;
      final firstSlots = bracket.rounds[0].pairings
          .map((p) => p.$1.participantId)
          .toList();
      expect(firstSlots, ['p1', 'p4', 'p3', 'p2']);
    });
  });
}
