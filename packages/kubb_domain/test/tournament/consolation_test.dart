import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

List<String> _ids(String prefix, int n) =>
    List.generate(n, (i) => '$prefix${i + 1}', growable: false);

/// All entries (both slots) of a round, flattened in slot order.
List<BracketEntry> _entries(BracketRound r) =>
    r.pairings.expand<BracketEntry>((p) => [p.$1, p.$2]).toList();

void main() {
  group('consolationDropTarget — ADR-0028 §2.2 worked examples', () {
    test('8er main bracket (mainSize=8, mainRounds=3)', () {
      // R1 (quarterfinal) -> consolation R1
      expect(consolationDropTarget(1, 1, 8), 1);
      expect(consolationDropTarget(1, 4, 8), 1, reason: 'round ignores position');
      // R2 (semifinal) -> 3rd-place playoff sentinel
      expect(consolationDropTarget(2, 1, 8), kConsolationThirdPlace);
      expect(consolationDropTarget(2, 1, 8), -1);
      // R3 (final) -> no consolation feed
      expect(consolationDropTarget(3, 1, 8), kConsolationNone);
      expect(consolationDropTarget(3, 1, 8), 0);
    });

    test('16er main bracket (mainSize=16, mainRounds=4)', () {
      expect(consolationDropTarget(1, 1, 16), 1); // octofinal -> cons R1
      expect(consolationDropTarget(2, 1, 16), 2); // quarterfinal -> cons R2
      expect(consolationDropTarget(3, 1, 16), kConsolationThirdPlace); // SF
      expect(consolationDropTarget(4, 1, 16), kConsolationNone); // final
    });

    test('target round does not depend on position', () {
      for (var p = 1; p <= 8; p++) {
        expect(consolationDropTarget(1, p, 16), 1);
        expect(consolationDropTarget(2, p, 16), 2);
      }
    });

    test('sentinels carry the documented values', () {
      expect(kConsolationThirdPlace, -1);
      expect(kConsolationNone, 0);
    });
  });

  group('consolationDropSlot — B-slot reflection ADR-0028 §3.3', () {
    test('always returns an odd (B-slot) index', () {
      for (var m = 1; m <= 8; m++) {
        for (var p = 1; p <= m; p++) {
          expect(consolationDropSlot(p, m).isOdd, isTrue,
              reason: 'loser docks into B-slot (A = survivor)');
        }
      }
    });

    test('reflects the main-round pairing order (anti-rematch)', () {
      // 16er §3.2: 4 QF losers dock into cons R2 (4 matches). Main pairing
      // index i (0-based) reflects to consolation pairing (M-1)-i, B-slot.
      const consMatches = 4;
      expect(consolationDropSlot(1, consMatches), (4 - 1 - 0) * 2 + 1); // ->7
      expect(consolationDropSlot(2, consMatches), (4 - 1 - 1) * 2 + 1); // ->5
      expect(consolationDropSlot(3, consMatches), (4 - 1 - 2) * 2 + 1); // ->3
      expect(consolationDropSlot(4, consMatches), (4 - 1 - 3) * 2 + 1); // ->1
    });

    test('maps each loser to a distinct B-slot (no collisions)', () {
      const consMatches = 4;
      final slots = {
        for (var p = 1; p <= consMatches; p++) consolationDropSlot(p, consMatches),
      };
      expect(slots, hasLength(consMatches));
    });

    test('matches the lbDropTarget reflection shape', () {
      // Same reflection algebra as lbDropTarget's B-slot pick, so Dart<->plpgsql
      // parity is the same trivial property as the LB feed.
      const consMatches = 2;
      expect(consolationDropSlot(1, consMatches), (2 - 1 - 0) * 2 + 1); // ->3
      expect(consolationDropSlot(2, consMatches), (2 - 1 - 1) * 2 + 1); // ->1
    });
  });

  group('consolationShape — staggered recurrence ADR-0028 §3.3', () {
    test('8er D=0: E_1=4,P_1=4,S_1=2; E_2=2,S_2=1; consRounds=2, bye-free', () {
      final s = consolationShape(8, 0);
      expect(s.consRounds, 2);
      expect(s.totalByes, 0);

      final r1 = s.shapes[0];
      expect(r1.round, 1);
      expect(r1.entrants, 4); // E_1 = D + L_1 = 0 + 4
      expect(r1.padded, 4); // P_1
      expect(r1.byes, 0);
      expect(r1.survivors, 2); // S_1
      expect(r1.matches, 2);

      final r2 = s.shapes[1];
      expect(r2.round, 2);
      expect(r2.entrants, 2); // E_2 = S_1 + L_2 = 2 + 0
      expect(r2.padded, 2);
      expect(r2.byes, 0);
      expect(r2.survivors, 1); // S_2 == 1 -> consRounds = 2
      expect(r2.matches, 1);
    });

    test('16er D=0: E=[8,8,4,2], S=[4,4,2,1]; consRounds=4, bye-free', () {
      final s = consolationShape(16, 0);
      expect(s.consRounds, 4);
      expect(s.totalByes, 0);

      expect(s.shapes.map((r) => r.entrants), [8, 8, 4, 2]);
      expect(s.shapes.map((r) => r.padded), [8, 8, 4, 2]);
      expect(s.shapes.map((r) => r.survivors), [4, 4, 2, 1]);
      expect(s.shapes.map((r) => r.matches), [4, 4, 2, 1]);
      expect(s.shapes.every((r) => r.byes == 0), isTrue);
    });

    test('it never uses next_pow2(total): 16er D=0 has 4 R1 matches not 8', () {
      // next_pow2(C) with C = 0 + 8 + 4 = 12 would wrongly yield 16 -> 8 R1
      // matches + 4 byes. The staggered recurrence yields 4 R1 matches, 0 byes.
      final s = consolationShape(16, 0);
      expect(s.shapes.first.matches, 4);
      expect(s.shapes.first.byes, 0);
    });

    test('it rejects non-power-of-two mainSize', () {
      expect(() => consolationShape(12, 0), throwsArgumentError);
    });

    test('it rejects negative directCount', () {
      expect(() => consolationShape(8, -1), throwsArgumentError);
    });
  });

  group('consolationShape — bye case (uneven D, ADR-0028 §4)', () {
    test('8er D=1: E_1=5 -> P_1=8, 3 byes in R1', () {
      // E_1 = 1 + 4 = 5 (not a power of two) -> P_1 = 8, byes = 3.
      final s = consolationShape(8, 1);
      final r1 = s.shapes.first;
      expect(r1.entrants, 5);
      expect(r1.padded, 8);
      expect(r1.byes, 3);
      expect(r1.survivors, 4);
      expect(r1.matches, 4);
    });

    test('8er D=3: E_1=7 -> P_1=8, 1 bye in R1', () {
      final s = consolationShape(8, 3);
      final r1 = s.shapes.first;
      expect(r1.entrants, 7);
      expect(r1.padded, 8);
      expect(r1.byes, 1);
      expect(r1.survivors, 4);
    });

    test('byes balance per round: sum equals total padding', () {
      final s = consolationShape(8, 1);
      // R1: E=5,P=8,byes=3 ; R2: E=S_1=4 (+L_2=0)=4,P=4,byes=0 ; ...
      expect(s.shapes.first.byes, 3);
      expect(s.totalByes, greaterThanOrEqualTo(3));
    });
  });

  group('Bracket.consolation — generation, seeding, byes', () {
    test('8er D=0: 4 R1 losers seed cons R1, 2 rounds, 3rd-place exists', () {
      final b = Bracket.consolation(
        8,
        r1LoserIds: _ids('l', 4),
      ) as ConsolationBracket;
      expect(b.rounds, hasLength(2));
      expect(b.rounds[0].number, 1);
      expect(b.rounds[0].phase, BracketPhase.consolation);
      expect(b.rounds[0].pairings, hasLength(2)); // 4 entrants, 2 matches
      expect(b.rounds[1].pairings, hasLength(1)); // consolation final
      expect(b.thirdPlace, isNotNull);
      expect(b.thirdPlace!.phase, BracketPhase.consolationThirdPlace);
      expect(b.thirdPlace!.pairings, hasLength(1));
      // No byes (E_1 = 4 is a power of two).
      expect(_entries(b.rounds[0]).where((e) => e.isBye), isEmpty);
      // All 4 R1 losers are placed in R1.
      final r1Ids = _entries(b.rounds[0])
          .map((e) => e.participantId)
          .whereType<String>()
          .toSet();
      expect(r1Ids, _ids('l', 4).toSet());
    });

    test('16er D=0: cons R1 has 4 matches (8 R1 losers), 4 rounds', () {
      final b = Bracket.consolation(
        16,
        r1LoserIds: _ids('l', 8),
      ) as ConsolationBracket;
      expect(b.rounds, hasLength(4));
      expect(b.rounds[0].pairings, hasLength(4)); // 8 entrants
      expect(b.rounds[1].pairings, hasLength(4)); // E_2 = 4 survivors + 4 QF
      expect(b.rounds[2].pairings, hasLength(2));
      expect(b.rounds[3].pairings, hasLength(1)); // consolation final
      expect(_entries(b.rounds[0]).where((e) => e.isBye), isEmpty);
    });

    test('later main losers are placeholders (B-slots filled at runtime)', () {
      // Only R1 losers known at generation; cons R2 docking slots stay empty.
      final b = Bracket.consolation(
        16,
        r1LoserIds: _ids('l', 8),
      ) as ConsolationBracket;
      final r2Ids = _entries(b.rounds[1])
          .map((e) => e.participantId)
          .whereType<String>();
      expect(r2Ids, isEmpty, reason: 'cons R2 is placeholder at generation');
    });

    test('direct starters seed cons R1 before R1 losers', () {
      // D=2 direct + 4 R1 losers => E_1 = 6 -> P_1 = 8, 2 byes at top seeds.
      final b = Bracket.consolation(
        8,
        directIds: const ['d1', 'd2'],
        r1LoserIds: _ids('l', 4),
      ) as ConsolationBracket;
      expect(b.rounds[0].pairings, hasLength(4)); // P_1 = 8 -> 4 matches
      final byeEntries =
          _entries(b.rounds[0]).where((e) => e.isBye).toList();
      expect(byeEntries, hasLength(2)); // P_1 - E_1 = 8 - 6
      // Byes face the top seeds (seed 1 = d1, seed 2 = d2) — FR-FMT-11.
      final byeOpponents = <int>{};
      for (final p in b.rounds[0].pairings) {
        if (p.$1.isBye && !p.$2.isBye) byeOpponents.add(p.$2.seed);
        if (p.$2.isBye && !p.$1.isBye) byeOpponents.add(p.$1.seed);
      }
      expect(byeOpponents, {1, 2});
      // Seed 1 / seed 2 carry the direct starters.
      final all = _entries(b.rounds[0]);
      final seed1 = all.firstWhere((e) => e.seed == 1);
      final seed2 = all.firstWhere((e) => e.seed == 2);
      expect(seed1.participantId, 'd1');
      expect(seed2.participantId, 'd2');
    });

    test('it is deterministic', () {
      final a = Bracket.consolation(16, r1LoserIds: _ids('l', 8));
      final b = Bracket.consolation(16, r1LoserIds: _ids('l', 8));
      expect(a, equals(b));
    });

    test('round count equals consRounds', () {
      for (final mainSize in [8, 16, 32]) {
        final shape = consolationShape(mainSize, 0);
        final b = Bracket.consolation(mainSize) as ConsolationBracket;
        expect(b.rounds, hasLength(shape.consRounds),
            reason: 'mainSize=$mainSize');
      }
    });

    test('4er main bracket D=0 has no consolation tree (ADR-0028 §6 small case)',
        () {
      // 4er: mainRounds=2, so the only non-final round is the SEMIFINAL, whose
      // losers go to the (main) 3rd-place playoff, never the consolation. With
      // D=0 the consolation has no entrants at all -> empty tree, no places 7/8.
      // E2 standings must not expect a consolation 3rd-place here.
      final shape = consolationShape(4, 0);
      expect(shape.consRounds, 0);
      final b = Bracket.consolation(4) as ConsolationBracket;
      expect(b.rounds, isEmpty);
      expect(b.thirdPlace, isNull,
          reason: 'no consolation semifinal => no 7/8 playoff');
    });

    test('thirdPlace materialises only when consRounds >= 2', () {
      // 8er D=0 -> consRounds=2 -> consolation semifinal exists -> 7/8 playoff.
      final shape = consolationShape(8, 0);
      expect(shape.consRounds, 2);
      final b = Bracket.consolation(8, r1LoserIds: _ids('l', 4))
          as ConsolationBracket;
      expect(b.thirdPlace, isNotNull);
    });

    test('empty tree (no direct, no losers given, 32er) still materialises',
        () {
      // With no R1 losers passed and D=0, the recurrence is still computed
      // from the main-bracket losers L_r -> non-empty placeholder tree.
      final b = Bracket.consolation(32) as ConsolationBracket;
      expect(b.rounds, isNotEmpty);
    });
  });

  group('bracketFromMatches — consolation projection (ADR-0028 §7.3)', () {
    KoMatchRow row({
      required int round,
      required int position,
      required BracketPhase phase,
      String? a,
      String? b,
    }) =>
        (
          roundNumber: round,
          bracketPosition: position,
          phase: phase,
          participantA: a,
          participantB: b,
          winnerParticipantId: null,
          isBye: a == null || b == null,
        );

    test('it reconstructs a ConsolationBracket from consolation rows', () {
      final rows = <KoMatchRow>[
        row(round: 1, position: 1, phase: BracketPhase.consolation, a: 'a', b: 'b'),
        row(round: 1, position: 2, phase: BracketPhase.consolation, a: 'c', b: 'd'),
        row(round: 2, position: 1, phase: BracketPhase.consolation),
        row(
            round: 1,
            position: 1,
            phase: BracketPhase.consolationThirdPlace),
      ];
      final b = bracketFromMatches(rows);
      expect(b, isA<ConsolationBracket>());
      final c = b as ConsolationBracket;
      expect(c.rounds, hasLength(2));
      expect(c.rounds[0].pairings, hasLength(2));
      expect(c.rounds[0].pairings[0].$1.participantId, 'a');
      expect(c.rounds[1].pairings, hasLength(1));
      expect(c.thirdPlace, isNotNull);
      expect(c.thirdPlace!.phase, BracketPhase.consolationThirdPlace);
    });

    test('it sorts pairings by bracket_position', () {
      final rows = <KoMatchRow>[
        row(round: 1, position: 2, phase: BracketPhase.consolation, a: 'c', b: 'd'),
        row(round: 1, position: 1, phase: BracketPhase.consolation, a: 'a', b: 'b'),
      ];
      final c = bracketFromMatches(rows) as ConsolationBracket;
      expect(c.rounds[0].pairings[0].$1.participantId, 'a');
      expect(c.rounds[0].pairings[1].$1.participantId, 'c');
    });

    test('consolation rows take precedence over single-elim path', () {
      final rows = <KoMatchRow>[
        row(round: 1, position: 1, phase: BracketPhase.winners, a: 'a', b: 'b'),
        row(round: 1, position: 1, phase: BracketPhase.consolation, a: 'x', b: 'y'),
      ];
      expect(bracketFromMatches(rows), isA<ConsolationBracket>());
    });

    test('no consolation 3rd-place row => thirdPlace is null', () {
      final rows = <KoMatchRow>[
        row(round: 1, position: 1, phase: BracketPhase.consolation, a: 'a', b: 'b'),
      ];
      final c = bracketFromMatches(rows) as ConsolationBracket;
      expect(c.thirdPlace, isNull);
    });
  });

  group('kBracketPhaseWire — consolation round-trip', () {
    test('it maps the two new consolation wire strings', () {
      expect(kBracketPhaseWire['consolation'], BracketPhase.consolation);
      expect(
        kBracketPhaseWire['consolation_third_place'],
        BracketPhase.consolationThirdPlace,
      );
    });

    test('it round-trips both markers', () {
      for (final p in [
        BracketPhase.consolation,
        BracketPhase.consolationThirdPlace,
      ]) {
        final wire =
            kBracketPhaseWire.entries.firstWhere((e) => e.value == p).key;
        expect(kBracketPhaseWire[wire], p);
      }
      expect(kBracketPhaseWire['consolation'], BracketPhase.consolation);
      expect(kBracketPhaseWire['consolation_third_place'],
          BracketPhase.consolationThirdPlace);
    });
  });
}
