import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

List<String> _ids(int n) =>
    List.generate(n, (i) => 'p${i + 1}', growable: false);

int _nextPow2(int n) {
  var size = 1;
  while (size < n) {
    size *= 2;
  }
  return size;
}

int _log2(int x) {
  var r = 0;
  var v = x;
  while (v > 1) {
    v ~/= 2;
    r++;
  }
  return r;
}

/// All entries (both slots) of a round, flattened in slot order.
List<BracketEntry> _entries(BracketRound r) =>
    r.pairings.expand<BracketEntry>((p) => [p.$1, p.$2]).toList();

void main() {
  group('Bracket.doubleElimination — structure sweep', () {
    const sizes = [2, 4, 6, 8, 16, 32];

    for (final n in sizes) {
      test('N=$n produces correct WB/LB round counts and slot counts', () {
        final b = Bracket.doubleElimination(_ids(n)) as DoubleEliminationBracket;
        final size = _nextPow2(n);
        final wbCount = _log2(size);
        final lbCount = 2 * (wbCount - 1);

        expect(b.wbRounds, hasLength(wbCount), reason: 'wbRounds for N=$n');
        expect(b.lbRounds, hasLength(lbCount), reason: 'lbRounds for N=$n');

        // WB round k has size/2^k matches.
        for (var k = 1; k <= wbCount; k++) {
          expect(
            b.wbRounds[k - 1].pairings,
            hasLength(size >> k),
            reason: 'WB-R$k match count for N=$n',
          );
          expect(b.wbRounds[k - 1].number, k);
          expect(b.wbRounds[k - 1].phase, BracketPhase.wb);
        }

        // LB closed form: minor j -> size/2^((j+3)/2), major j -> size/2^((j+2)/2).
        for (var j = 1; j <= lbCount; j++) {
          final expected =
              j.isOdd ? size >> ((j + 3) ~/ 2) : size >> ((j + 2) ~/ 2);
          expect(
            b.lbRounds[j - 1].pairings,
            hasLength(expected),
            reason: 'LB-R$j match count for N=$n',
          );
          expect(b.lbRounds[j - 1].number, j);
          expect(b.lbRounds[j - 1].phase, BracketPhase.lb);
        }

        // Last LB round is the LB final: exactly 1 match (when LB exists).
        if (lbCount > 0) {
          expect(b.lbRounds.last.pairings, hasLength(1));
        }
      });
    }

    test('it is deterministic', () {
      final a = Bracket.doubleElimination(_ids(6));
      final b = Bracket.doubleElimination(_ids(6));
      expect(a, equals(b));
    });

    test('WB rounds equal single-elim rounds modulo phase', () {
      for (final n in [2, 4, 6, 8, 16]) {
        final de =
            Bracket.doubleElimination(_ids(n)) as DoubleEliminationBracket;
        final se =
            Bracket.singleElimination(_ids(n)) as SingleEliminationBracket;
        expect(de.wbRounds, hasLength(se.rounds.length));
        for (var i = 0; i < se.rounds.length; i++) {
          expect(de.wbRounds[i].number, se.rounds[i].number);
          expect(de.wbRounds[i].pairings, se.rounds[i].pairings,
              reason: 'WB pairings must match single-elim for N=$n round $i');
          expect(de.wbRounds[i].phase, BracketPhase.wb);
        }
      }
    });

    test('single-elimination regression: unchanged by new code', () {
      final b = Bracket.singleElimination(_ids(8)) as SingleEliminationBracket;
      expect(b.rounds.map((r) => r.number), [1, 2, 3]);
      expect(b.rounds[0].pairings, hasLength(4));
      expect(b.rounds[2].pairings, hasLength(1));
      expect(b.rounds.every((r) => r.phase == BracketPhase.winners), isTrue);
    });
  });

  group('Bracket.doubleElimination — grand final reset toggle', () {
    test('withBracketReset=true materialises exactly one reset pairing', () {
      final b = Bracket.doubleElimination(_ids(8)) as DoubleEliminationBracket;
      expect(b.withBracketReset, isTrue);
      expect(b.grandFinal.phase, BracketPhase.grandFinal);
      expect(b.grandFinal.pairings, hasLength(1));
      expect(b.grandFinalReset, isNotNull);
      expect(b.grandFinalReset!.phase, BracketPhase.grandFinalReset);
      expect(b.grandFinalReset!.pairings, hasLength(1));
    });

    test('withBracketReset=false leaves grandFinalReset null', () {
      final b = Bracket.doubleElimination(_ids(8), withBracketReset: false)
          as DoubleEliminationBracket;
      expect(b.withBracketReset, isFalse);
      expect(b.grandFinalReset, isNull);
      expect(b.grandFinal.pairings, hasLength(1));
    });
  });

  group('lbDropTarget — bijective drop-mapping & anti-rematch', () {
    test('WB round k>=2 losers map bijectively onto LB-R(2k-2) B-slots', () {
      for (final size in [4, 8, 16, 32]) {
        final wbCount = _log2(size);
        for (var k = 2; k <= wbCount; k++) {
          final lbMatches = size >> k;
          final targets = <int>{};
          for (var p = 1; p <= lbMatches; p++) {
            final slot = lbDropTarget(k, p, size);
            // Always a B-slot.
            expect(slot.isOdd, isTrue,
                reason: 'WB-R$k pos$p must drop into a B-slot (size=$size)');
            final pairing = slot ~/ 2;
            expect(pairing, inInclusiveRange(0, lbMatches - 1));
            targets.add(slot);
          }
          // Bijective: lbMatches distinct B-slots.
          expect(targets, hasLength(lbMatches),
              reason: 'drop targets must be distinct for WB-R$k (size=$size)');
        }
      }
    });

    test('anti-rematch: drop order is reflected vs WB pairing order', () {
      // For size=8, WB-R2 has 2 matches (pos 1,2) dropping into LB-R2 (2 B-slots).
      // Reflection => pos1 -> last pairing B-slot, pos2 -> first pairing B-slot.
      expect(lbDropTarget(2, 1, 8), 1 * 2 + 1); // pairing 1 (index 1), B
      expect(lbDropTarget(2, 2, 8), 0 * 2 + 1); // pairing 0, B
      // WB-R3 (final) single loser -> LB-R4 single B-slot.
      expect(lbDropTarget(3, 1, 8), 1);
    });
  });

  group('Bracket.doubleElimination — worked example N=8 (ADR-0027 §1.7)', () {
    late DoubleEliminationBracket b;
    setUp(() {
      b = Bracket.doubleElimination(_ids(8)) as DoubleEliminationBracket;
    });

    test('it has 0 byes, 3 WB rounds, 4 LB rounds', () {
      expect(b.wbRounds, hasLength(3));
      expect(b.lbRounds, hasLength(4));
      final byes = _entries(b.wbRounds.first).where((e) => e.isBye).length;
      expect(byes, 0);
    });

    test('match totals: WB=7, LB=6, GF=1, reset=1 (=15 with reset)', () {
      final wb = b.wbRounds.fold<int>(0, (s, r) => s + r.pairings.length);
      final lb = b.lbRounds.fold<int>(0, (s, r) => s + r.pairings.length);
      expect(wb, 7); // 4 + 2 + 1
      expect(lb, 6); // 2 + 2 + 1 + 1
      const gf = 1;
      final reset = b.grandFinalReset == null ? 0 : 1;
      expect(wb + lb + gf + reset, 15);
    });

    test('WB-R1 ordering follows recursive seeding [1,8,5,4,3,6,7,2]', () {
      final seeds = _entries(b.wbRounds.first).map((e) => e.seed).toList();
      expect(seeds, [1, 8, 5, 4, 3, 6, 7, 2]);
    });

    test('LB slot counts are [2,2,1,1]', () {
      expect(b.lbRounds.map((r) => r.pairings.length), [2, 2, 1, 1]);
    });
  });

  group('Bracket.doubleElimination — worked example N=6 (ADR-0027 §1.8)', () {
    late DoubleEliminationBracket b;
    setUp(() {
      b = Bracket.doubleElimination(_ids(6)) as DoubleEliminationBracket;
    });

    test('it pads to size 8: 2 byes, 3 WB rounds, 4 LB rounds', () {
      expect(b.wbRounds, hasLength(3));
      expect(b.lbRounds, hasLength(4));
      final byes = _entries(b.wbRounds.first).where((e) => e.isBye).length;
      expect(byes, 2);
    });

    test('each WB-R1 BYE produces exactly one LB-R1 BYE slot', () {
      final wbByes = _entries(b.wbRounds.first).where((e) => e.isBye).length;
      final lbR1Byes =
          _entries(b.lbRounds.first).where((e) => e.isBye).length;
      expect(lbR1Byes, wbByes);
      expect(lbR1Byes, 2);
    });
  });

  group('Bracket.doubleElimination — BYE positions for non-2^n', () {
    // FR-FMT-11: byes sit at top seeds in the WB (reuses single-elim).
    for (final n in [3, 5, 6, 7]) {
      test('N=$n: #LB-R1 byes == byes == size-N and byes pair top seeds', () {
        final b =
            Bracket.doubleElimination(_ids(n)) as DoubleEliminationBracket;
        final size = _nextPow2(n);
        final byes = size - n;

        // WB byes equal padding.
        final wbByeEntries =
            _entries(b.wbRounds.first).where((e) => e.isBye).toList();
        expect(wbByeEntries, hasLength(byes), reason: 'WB byes for N=$n');

        // Byes pair against top seeds: the non-bye opponents of bye matches
        // are the top `byes` seeds.
        final byeOpponentSeeds = <int>{};
        for (final p in b.wbRounds.first.pairings) {
          if (p.$1.isBye && !p.$2.isBye) byeOpponentSeeds.add(p.$2.seed);
          if (p.$2.isBye && !p.$1.isBye) byeOpponentSeeds.add(p.$1.seed);
        }
        expect(
          byeOpponentSeeds,
          {for (var s = 1; s <= byes; s++) s},
          reason: 'byes must face the top $byes seeds for N=$n',
        );

        // Each WB-R1 bye => exactly one LB-R1 bye slot; total == byes.
        final lbR1Byes =
            _entries(b.lbRounds.first).where((e) => e.isBye).length;
        expect(lbR1Byes, byes, reason: 'LB-R1 byes for N=$n');
      });
    }
  });

  group('Bracket.doubleElimination — participant uniqueness', () {
    for (final n in [2, 4, 6, 8, 16, 32]) {
      test('N=$n: each real participant appears at most once in WB-R1', () {
        final b =
            Bracket.doubleElimination(_ids(n)) as DoubleEliminationBracket;
        final ids = _entries(b.wbRounds.first)
            .map((e) => e.participantId)
            .whereType<String>()
            .toList();
        expect(ids.toSet(), hasLength(ids.length));
        expect(ids.toSet(), _ids(n).toSet());
      });
    }
  });

  group('Bracket.doubleElimination — edge cases', () {
    test('it throws on empty participants', () {
      expect(() => Bracket.doubleElimination(const []), throwsArgumentError);
    });

    test('N=1 yields empty WB/LB but a grand final round', () {
      final b = Bracket.doubleElimination(_ids(1)) as DoubleEliminationBracket;
      expect(b.wbRounds, isEmpty);
      expect(b.lbRounds, isEmpty);
      expect(b.grandFinal.pairings, hasLength(1));
    });

    test('N=2: lbRounds is empty (pure GF)', () {
      final b = Bracket.doubleElimination(_ids(2)) as DoubleEliminationBracket;
      expect(b.wbRounds, hasLength(1));
      expect(b.lbRounds, isEmpty);
      expect(b.grandFinal.pairings, hasLength(1));
    });
  });

  group('bracketFromMatches — double-elim round-trip', () {
    test('it reconstructs a DoubleEliminationBracket from DE phases', () {
      final rows = <KoMatchRow>[
        (
          roundNumber: 1,
          bracketPosition: 1,
          phase: BracketPhase.wb,
          participantA: 'a',
          participantB: 'b',
          winnerParticipantId: null,
          isBye: false,
        ),
        (
          roundNumber: 1,
          bracketPosition: 1,
          phase: BracketPhase.lb,
          participantA: null,
          participantB: null,
          winnerParticipantId: null,
          isBye: false,
        ),
        (
          roundNumber: 1,
          bracketPosition: 1,
          phase: BracketPhase.grandFinal,
          participantA: null,
          participantB: null,
          winnerParticipantId: null,
          isBye: false,
        ),
        (
          roundNumber: 1,
          bracketPosition: 1,
          phase: BracketPhase.grandFinalReset,
          participantA: null,
          participantB: null,
          winnerParticipantId: null,
          isBye: false,
        ),
      ];
      final b = bracketFromMatches(rows);
      expect(b, isA<DoubleEliminationBracket>());
      final de = b as DoubleEliminationBracket;
      expect(de.wbRounds, hasLength(1));
      expect(de.lbRounds, hasLength(1));
      expect(de.withBracketReset, isTrue);
      expect(de.grandFinalReset, isNotNull);
    });

    test('single-elim rows still build a SingleEliminationBracket', () {
      final rows = <KoMatchRow>[
        (
          roundNumber: 1,
          bracketPosition: 1,
          phase: BracketPhase.winners,
          participantA: 'a',
          participantB: 'b',
          winnerParticipantId: null,
          isBye: false,
        ),
      ];
      expect(bracketFromMatches(rows), isA<SingleEliminationBracket>());
    });
  });

  group('kBracketPhaseWire', () {
    test('it maps the four new DE wire values', () {
      expect(kBracketPhaseWire['wb'], BracketPhase.wb);
      expect(kBracketPhaseWire['lb'], BracketPhase.lb);
      expect(kBracketPhaseWire['grand_final'], BracketPhase.grandFinal);
      expect(
        kBracketPhaseWire['grand_final_reset'],
        BracketPhase.grandFinalReset,
      );
    });
  });
}
