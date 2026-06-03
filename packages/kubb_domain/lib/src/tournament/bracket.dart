import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Standard sport-tournament seeding (top-seed faces top of the
/// opposite half, so seed 1 and seed 2 only meet in the final).
/// The linear pattern pairs `(seed_i, seed_{N+1-i})` straight through,
/// which lets high seeds meet earlier — easier to compute, but
/// uncommon in real tournaments.
enum BracketSeedingPattern { recursive, linear }

/// Phase marker for a [BracketRound] — see ADR-0017 §4 (single-elim) and
/// ADR-0027 (double-elim). `winners`/`finals`/`thirdPlace` remain for
/// single-elim; the four new values are double-elim-specific.
enum BracketPhase {
  winners,
  thirdPlace,
  finals,
  // Double-Elimination (ADR-0027 §1):
  wb, // winner bracket round
  lb, // loser bracket round (major + minor)
  grandFinal, // GF game 1
  grandFinalReset, // GF game 2 (only materialised when with_bracket_reset)
  // Consolation / Trostturnier (ADR-0028 §7.1): the consolation rounds carry
  // `consolation`; its 3rd-place playoff carries its OWN phase
  // `consolationThirdPlace`. The two are NOT folded into `thirdPlace`/
  // `consolation` + round_number, because consRounds can equal mainRounds (e.g.
  // an 8er main bracket with enough direct starters), which would collide on
  // (phase, round_number). phase stays the SOLE discriminator (ADR-0017/0027).
  consolation, // consolation (Trostturnier) round
  consolationThirdPlace, // consolation 3rd-place playoff (own phase)
}

/// Wire-Mapping (DB phase text <-> [BracketPhase]). Single source of truth
/// for repository adapters and plpgsql parity (ADR-0027 §1.1).
const Map<String, BracketPhase> kBracketPhaseWire = {
  'group': BracketPhase.winners, // group is never mapped as a KO row
  'ko': BracketPhase.winners,
  'final': BracketPhase.finals,
  'third_place': BracketPhase.thirdPlace,
  'wb': BracketPhase.wb,
  'lb': BracketPhase.lb,
  'grand_final': BracketPhase.grandFinal,
  'grand_final_reset': BracketPhase.grandFinalReset,
  'consolation': BracketPhase.consolation, // ADR-0028 §7.1
  'consolation_third_place': BracketPhase.consolationThirdPlace, // ADR-0028 §7.1
};

typedef BracketEntry = ({int seed, String? participantId, bool isBye});
typedef BracketPairing = (BracketEntry a, BracketEntry b);

@immutable
final class BracketRound {
  const BracketRound({
    required this.number,
    required this.pairings,
    this.phase = BracketPhase.winners,
  });

  final int number;
  final List<BracketPairing> pairings;
  final BracketPhase phase;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BracketRound &&
          other.number == number &&
          other.phase == phase &&
          const ListEquality<BracketPairing>()
              .equals(other.pairings, pairings);

  @override
  int get hashCode => Object.hash(number, phase, Object.hashAll(pairings));
}

@immutable
sealed class Bracket {
  const Bracket();

  factory Bracket.singleElimination(
    List<String> participantIds, {
    bool withThirdPlace = false,
    BracketSeedingPattern seedingPattern = BracketSeedingPattern.recursive,
  }) {
    if (participantIds.isEmpty) {
      throw ArgumentError.value(participantIds, 'participantIds', 'is empty');
    }
    final n = participantIds.length;
    if (n == 1) return const SingleEliminationBracket(rounds: []);
    var size = 1;
    while (size < n) {
      size *= 2;
    }
    final slots = <BracketEntry>[
      for (var i = 0; i < size; i++)
        (
          seed: i + 1,
          participantId: i < n ? participantIds[i] : null,
          isBye: i >= n,
        ),
    ];
    final order = switch (seedingPattern) {
      BracketSeedingPattern.linear => [
          for (var i = 0; i < size ~/ 2; i++) ...[i + 1, size - i],
        ],
      BracketSeedingPattern.recursive => _standardBracketOrder(size),
    };
    final round1 = <BracketPairing>[
      for (var i = 0; i < size; i += 2)
        (slots[order[i] - 1], slots[order[i + 1] - 1]),
    ];
    const placeholder = (seed: 0, participantId: null, isBye: false);
    var totalRounds = 0;
    for (var x = size; x > 1; x ~/= 2) {
      totalRounds++;
    }
    final rounds = <BracketRound>[
      BracketRound(number: 1, pairings: round1),
      for (var r = 2; r <= totalRounds; r++)
        BracketRound(
          number: r,
          pairings: List.generate(
            size ~/ (1 << r),
            (_) => (placeholder, placeholder),
          ),
        ),
      if (withThirdPlace)
        BracketRound(
          number: totalRounds,
          pairings: const [(placeholder, placeholder)],
          phase: BracketPhase.thirdPlace,
        ),
    ];
    return SingleEliminationBracket(rounds: rounds);
  }

  /// Build a double-elimination bracket from [participantIds] (ADR-0027 §1).
  ///
  /// The winner bracket (WB) reuses [Bracket.singleElimination] verbatim
  /// (recursive seeding, BYEs at top seeds) — only the phase is rewritten to
  /// [BracketPhase.wb]. The loser bracket (LB) is generated as empty
  /// placeholder rounds following the major/minor scheme (§1.3); LB-R1 slots
  /// fed by a WB-R1 BYE match are pre-marked as BYE (§1.5). Grand final and the
  /// optional grand-final reset are single-pairing placeholder rounds.
  ///
  /// Slot-by-slot fill from match outcomes is the server trigger's job at
  /// runtime — exactly like [Bracket.singleElimination] only materialises R1
  /// and leaves R2+ as placeholders.
  factory Bracket.doubleElimination(
    List<String> participantIds, {
    bool withBracketReset = true,
    BracketSeedingPattern seedingPattern = BracketSeedingPattern.recursive,
  }) {
    if (participantIds.isEmpty) {
      throw ArgumentError.value(participantIds, 'participantIds', 'is empty');
    }
    const placeholder = (seed: 0, participantId: null, isBye: false);
    final n = participantIds.length;
    if (n == 1) {
      // Single participant => no contest. GF round still carries the structure
      // for callers that expect a non-null grand final.
      return DoubleEliminationBracket(
        wbRounds: const [],
        lbRounds: const [],
        grandFinal: const BracketRound(
          number: 1,
          phase: BracketPhase.grandFinal,
          pairings: [(placeholder, placeholder)],
        ),
        grandFinalReset: withBracketReset
            ? const BracketRound(
                number: 1,
                phase: BracketPhase.grandFinalReset,
                pairings: [(placeholder, placeholder)],
              )
            : null,
        withBracketReset: withBracketReset,
      );
    }

    var size = 1;
    while (size < n) {
      size *= 2;
    }

    // --- WB: reuse single-elim 1:1, only relabel the phase to wb. ---
    final se = Bracket.singleElimination(
      participantIds,
      seedingPattern: seedingPattern,
    ) as SingleEliminationBracket;
    final wbRounds = <BracketRound>[
      for (final r in se.rounds)
        BracketRound(
          number: r.number,
          phase: BracketPhase.wb,
          pairings: r.pairings,
        ),
    ];
    final wbCount = wbRounds.length; // == log2(size)

    // --- LB: empty placeholder rounds per the major/minor closed form. ---
    final lbCount = 2 * (wbCount - 1);
    final lbRounds = <BracketRound>[
      for (var j = 1; j <= lbCount; j++)
        BracketRound(
          number: j,
          phase: BracketPhase.lb,
          pairings: List.generate(
            // minor (odd j): size / 2^((j+3)/2); major (even j): size / 2^((j+2)/2)
            j.isOdd ? size >> ((j + 3) ~/ 2) : size >> ((j + 2) ~/ 2),
            (_) => (placeholder, placeholder),
          ),
        ),
    ];

    // --- Pre-mark LB-R1 BYE slots for every WB-R1 BYE pairing (§1.5). ---
    if (lbRounds.isNotEmpty) {
      final wbR1 = wbRounds.first.pairings;
      final lbR1 = [...lbRounds.first.pairings];
      for (var p = 1; p <= wbR1.length; p++) {
        final pair = wbR1[p - 1];
        if (!pair.$1.isBye && !pair.$2.isBye) continue;
        // BYE-winning WB-R1 match feeds no real loser => LB-R1 slot is a BYE.
        final slot = _lbR1DropSlot(p, size);
        final pairIdx = slot ~/ 2;
        final slotIdx = slot % 2;
        const bye = (seed: 0, participantId: null, isBye: true);
        final cur = lbR1[pairIdx];
        lbR1[pairIdx] = (
          slotIdx == 0 ? bye : cur.$1,
          slotIdx == 1 ? bye : cur.$2,
        );
      }
      lbRounds[0] = BracketRound(
        number: 1,
        phase: BracketPhase.lb,
        pairings: lbR1,
      );
    }

    const grandFinal = BracketRound(
      number: 1,
      phase: BracketPhase.grandFinal,
      pairings: [(placeholder, placeholder)],
    );
    final grandFinalReset = withBracketReset
        ? const BracketRound(
            number: 1,
            phase: BracketPhase.grandFinalReset,
            pairings: [(placeholder, placeholder)],
          )
        : null;

    return DoubleEliminationBracket(
      wbRounds: wbRounds,
      lbRounds: lbRounds,
      grandFinal: grandFinal,
      grandFinalReset: grandFinalReset,
      withBracketReset: withBracketReset,
    );
  }

  /// Build a consolation (Trostturnier, Model B) bracket (ADR-0028).
  ///
  /// Combines the [directIds] direct starters (preliminary qualifiers entering
  /// the consolation directly, highest prelim rank first) and the staggered
  /// main-bracket losers into ONE tree. The main bracket itself is NOT built
  /// here — only the consolation tree is materialised (the main single-elim
  /// stays the unchanged [Bracket.singleElimination] output, §1.1).
  ///
  /// Topology follows the staggered-aware recurrence ([consolationShape],
  /// §3.3) — NOT `next_pow2(total)`. Direct starters + main-bracket R1 losers
  /// seed round 1 via `_standardBracketOrder(P_1)` (recursive seeding, byes at
  /// top seeds, §3.3/§4). Later main-bracket rounds (`r >= 2`) dock their
  /// losers as B-slots of their target consolation round (A-slot = consolation
  /// survivor of the prior round) — placeholders here, filled by the server
  /// trigger at runtime. The consolation 3rd-place playoff carries its own
  /// phase [BracketPhase.consolationThirdPlace].
  ///
  /// [mainSize] is the power-of-two main-bracket size. [r1LoserIds] are the
  /// main-bracket R1 losers already known at generation time (typically empty
  /// — the trigger fills them as the main R1 finalises); when given they are
  /// seeded into consolation R1 after the direct starters (§3.3 step 2).
  /// [withThirdPlace] materialises the consolation 3rd-place playoff (default
  /// true, mirroring the §6 ranking layout).
  factory Bracket.consolation(
    int mainSize, {
    List<String> directIds = const <String>[],
    List<String> r1LoserIds = const <String>[],
    bool withThirdPlace = true,
    BracketSeedingPattern seedingPattern = BracketSeedingPattern.recursive,
  }) {
    final shape = consolationShape(mainSize, directIds.length);
    const placeholder = (seed: 0, participantId: null, isBye: false);
    if (shape.shapes.isEmpty) {
      return const ConsolationBracket(rounds: [], thirdPlace: null);
    }

    // --- Round 1: seed direct starters + main-R1 losers, byes at top seeds.
    final r1 = shape.shapes.first;
    // Seed order: direct starters first (best prelim rank = seed 1), then the
    // R1 losers by main-bracket seed (§3.3 step 2).
    final seeded = <String>[...directIds, ...r1LoserIds];
    final p1 = r1.padded;
    final slots = <BracketEntry>[
      for (var i = 0; i < p1; i++)
        (
          seed: i + 1,
          participantId: i < seeded.length ? seeded[i] : null,
          isBye: i >= seeded.length, // byes pad the bottom seeds...
        ),
    ];
    final order = switch (seedingPattern) {
      BracketSeedingPattern.linear => [
          for (var i = 0; i < p1 ~/ 2; i++) ...[i + 1, p1 - i],
        ],
      BracketSeedingPattern.recursive => _standardBracketOrder(p1),
    };
    // ...so via recursive seeding the byes face the TOP seeds (FR-FMT-11).
    final round1 = <BracketPairing>[
      for (var i = 0; i < p1; i += 2)
        (slots[order[i] - 1], slots[order[i + 1] - 1]),
    ];

    final rounds = <BracketRound>[
      BracketRound(
        number: 1,
        phase: BracketPhase.consolation,
        pairings: round1,
      ),
      // Rounds r >= 2 are bare placeholders here: the A-slot (consolation
      // survivor of round r-1) and the B-slot (staggered main-round-r loser,
      // reflected via [consolationDropSlot]) are both filled by the server
      // trigger at runtime (ADR-0028 §3.3/§7.4). This deliberately mirrors the
      // doubleElimination factory, where LB-R2+ are likewise bare placeholders
      // and the slot fill is the trigger's job. Only the match COUNT per round
      // (from [consolationShape]) is materialised here.
      for (var i = 1; i < shape.shapes.length; i++)
        BracketRound(
          number: shape.shapes[i].round,
          phase: BracketPhase.consolation,
          pairings: List.generate(
            shape.shapes[i].matches,
            (_) => (placeholder, placeholder),
          ),
        ),
    ];

    // Consolation 3rd-place playoff only exists when there is a consolation
    // semifinal (>= 2 rounds) — otherwise the tree has no losers to rank 7/8.
    final thirdPlace = (withThirdPlace && shape.consRounds >= 2)
        ? const BracketRound(
            number: 1,
            phase: BracketPhase.consolationThirdPlace,
            pairings: [(placeholder, placeholder)],
          )
        : null;

    return ConsolationBracket(rounds: rounds, thirdPlace: thirdPlace);
  }

  /// Place [participantId] into slot ([round], [position]). 1-based indices.
  ///
  /// [round] targets a [BracketRound] whose `phase` is not
  /// [BracketPhase.thirdPlace]. [position] is 1-based across the round's
  /// pairings: position 1 = first pairing's `$1`, 2 = first pairing's `$2`,
  /// 3 = second pairing's `$1`, ...
  ///
  /// Pure: returns a new [Bracket] with the slot replaced; all other slots
  /// remain identical. When the filled slot belongs to the FINAL round (the
  /// last winners round) of a bracket that also carries a
  /// [BracketPhase.thirdPlace] round, the corresponding loser of the
  /// feeding semifinal pairing is mirrored into the third-place slot —
  /// see ADR-0017 §4/§5. Filling earlier winners rounds has no side effect
  /// on the third-place pairing.
  Bracket fill({
    required int round,
    required int position,
    required String participantId,
  });
}

/// Returns the 0-based LB slot (pairing-index * 2 + side) in LB round `2k-2`
/// (major) into which the loser of `bracket_position` [wbPosition] (1-based) of
/// WB round [wbRound] (`k >= 2`) drops (ADR-0027 §1.4). [size] is the padded
/// power-of-two bracket size. `lbMatchesInTarget = size / 2^k`.
///
/// Anti-rematch: the pairing order of fed-in losers is reflected relative to
/// the LB slot order. The WB loser always occupies the B-slot of a major LB
/// pairing (A = the LB survivor). Pure function of `(wbRound, wbPosition, size)`
/// — identical in Dart and plpgsql so property parity stays trivially testable.
int lbDropTarget(int wbRound, int wbPosition, int size) {
  final k = wbRound;
  final lbMatches = size >> k; // size / 2^k
  final i = wbPosition - 1; // 0-based WB pairing index in its round
  final lbPairing = (lbMatches - 1) - i; // reflection
  return lbPairing * 2 + 1; // +1 => B-slot
}

/// Returns the 0-based LB-R1 slot (pairing-index * 2 + side) into which the
/// loser of WB-R1 `bracket_position` [wbPosition] (1-based) drops (ADR-0027
/// §1.4). Both losers of a WB slot-pair meet each other in LB-R1; the upper WB
/// halves are reflected into the lower LB-R1 pairings and vice versa. [size] is
/// the padded bracket size, LB-R1 has `size/4` pairings.
int _lbR1DropSlot(int wbPosition, int size) {
  final lbMatches = size >> 2; // size / 4
  final i = wbPosition - 1; // 0-based WB-R1 pairing index
  final lbPairing = (lbMatches - 1) - (i ~/ 2); // reflect between halves
  final side = i % 2; // even => A, odd => B
  return lbPairing * 2 + side;
}

// --- Consolation / Trostturnier (ADR-0028) -------------------------------

/// Sentinels for the consolation drop target (ADR-0028 §2).
const int kConsolationThirdPlace = -1; // semifinal loser -> 3rd-place playoff
const int kConsolationNone = 0; // final / no consolation feed

/// Closed-form, pure mapping (ADR-0028 §2.2): which consolation round a loser of
/// main-bracket round [mainRound] (1-based) enters. [mainSize] is the
/// power-of-two main-bracket size; [position] is the 1-based pairing index in
/// the main round (kept for parity with [lbDropTarget]; the target ROUND does
/// not depend on it — only the within-round seeding/slot does, see §3.3).
///
/// mainRounds = log2(mainSize). Round mainRounds-1 = semifinal (its losers go to
/// the third-place playoff, NOT the consolation), round mainRounds = final.
///
/// The return value is the target consolation ROUND, not a slot. Staggered feed
/// (major/minor mechanic, like the LB in ADR-0027 §1.3): a loser eliminated in
/// main round `r` (1 <= r <= mainRounds-2) enters consolation round `r`. For
/// r == 1 the loser is one of the consolation-R1 entrants (seeded via §3.3). For
/// r >= 2 the loser does NOT open a fresh consolation-R`r` pairing; it occupies
/// the B-slot of a pairing whose A-slot is the consolation survivor of the prior
/// round (the round is then sized recursively, §3.3 — never via
/// next_pow2(total)).
int consolationDropTarget(int mainRound, int position, int mainSize) {
  final mainRounds = _log2(mainSize);
  if (mainRound >= mainRounds) return kConsolationNone; // final -> P1/P2
  if (mainRound == mainRounds - 1) {
    return kConsolationThirdPlace; // semifinal
  }
  // Feeding rounds 1..mainRounds-2 map 1:1 onto consolation rounds.
  return mainRound; // consolation round index (1-based)
}

/// Closed-form B-slot reflection for a staggered consolation feed (ADR-0028
/// §3.3) — the slot analogue of [lbDropTarget].
///
/// While [consolationDropTarget] returns the target consolation ROUND, this
/// returns the 0-based slot (pairing-index * 2 + side) inside that round into
/// which the loser of main-bracket round `r >= 2`, `bracket_position`
/// [mainPosition] (1-based), docks. The loser always occupies the B-slot of a
/// consolation pairing whose A-slot is the consolation survivor of the prior
/// round (major-round mechanic, ADR-0028 §3.3 / ADR-0027 §1.4). [consMatches]
/// is the number of pairings in the target consolation round
/// (`P_r / 2` from [consolationShape]).
///
/// Anti-rematch: the main-round pairing order is reflected onto the consolation
/// pairing order, exactly like [lbDropTarget] reflects WB onto LB. Pure
/// function of `(mainPosition, consMatches)` — identical in Dart and plpgsql so
/// property parity stays trivially testable. Only meaningful for the staggered
/// feed (`mainRound >= 2`); for `mainRound == 1` the loser is seeded into
/// consolation R1 via `_standardBracketOrder` (§3.3 step 2), not docked.
int consolationDropSlot(int mainPosition, int consMatches) {
  final i = mainPosition - 1; // 0-based main pairing index in its round
  final consPairing = (consMatches - 1) - i; // reflection (anti-rematch)
  return consPairing * 2 + 1; // +1 => B-slot (A = consolation survivor)
}

int _log2(int n) {
  var r = 0;
  var x = n;
  while (x > 1) {
    x >>= 1;
    r++;
  }
  return r;
}

int _nextPow2(int n) {
  var size = 1;
  while (size < n) {
    size *= 2;
  }
  return size;
}

/// Per-round structure numbers of the consolation tree (ADR-0028 §3.3).
///
/// One entry per consolation round `r` (1-based). [entrants] is `E_r`
/// (survivors `S_{r-1}` + freshly-fed losers `L_r`), [padded] is
/// `P_r = next_pow2(E_r)`, [byes] is `P_r - E_r`, [survivors] is `S_r = P_r/2`,
/// [matches] is `P_r/2`.
@immutable
final class ConsolationRoundShape {
  const ConsolationRoundShape({
    required this.round,
    required this.entrants,
    required this.padded,
    required this.byes,
    required this.survivors,
    required this.matches,
  });

  final int round;
  final int entrants; // E_r
  final int padded; // P_r = next_pow2(E_r)
  final int byes; // P_r - E_r
  final int survivors; // S_r = P_r / 2
  final int matches; // P_r / 2

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConsolationRoundShape &&
          other.round == round &&
          other.entrants == entrants &&
          other.padded == padded &&
          other.byes == byes &&
          other.survivors == survivors &&
          other.matches == matches;

  @override
  int get hashCode =>
      Object.hash(round, entrants, padded, byes, survivors, matches);
}

/// The full staggered-aware recurrence of the consolation tree (ADR-0028 §3.3).
///
/// [shapes] is one [ConsolationRoundShape] per consolation round (1-based);
/// [consRounds] == `shapes.length` == smallest `r` with `S_r == 1`.
@immutable
final class ConsolationShape {
  const ConsolationShape({required this.shapes});

  final List<ConsolationRoundShape> shapes;

  int get consRounds => shapes.length;
  int get totalByes => shapes.fold<int>(0, (s, r) => s + r.byes);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConsolationShape &&
          const ListEquality<ConsolationRoundShape>()
              .equals(other.shapes, shapes);

  @override
  int get hashCode => Object.hashAll(shapes);
}

/// Compute the staggered-aware consolation recurrence (ADR-0028 §3.3).
///
/// `L_r = mainSize / 2^r` for `r in 1..mainRounds-2` (main-bracket losers fed
/// from main round `r`), `L_r = 0` otherwise (the semifinal feeds the
/// third-place playoff, not the consolation). `E_1 = directCount + L_1`,
/// `P_r = next_pow2(E_r)`, `S_r = P_r/2`, `E_r = S_{r-1} + L_r` for `r >= 2`.
/// `consRounds` is the smallest `r` with `S_r == 1`. The tree size is derived
/// from the EARLIEST-round population (never `next_pow2(total)`); the total
/// participant count `C` is only ever used for the per-round bye balance.
///
/// [mainSize] must be a power of two; [directCount] (`D`) must be `>= 0`.
ConsolationShape consolationShape(int mainSize, int directCount) {
  if (mainSize < 2 || (mainSize & (mainSize - 1)) != 0) {
    throw ArgumentError.value(mainSize, 'mainSize', 'must be a power of two');
  }
  if (directCount < 0) {
    throw ArgumentError.value(directCount, 'directCount', 'must be >= 0');
  }
  final mainRounds = _log2(mainSize);
  // L_r = mainSize / 2^r for feeding rounds 1..mainRounds-2, else 0.
  int losersFrom(int r) =>
      (r >= 1 && r <= mainRounds - 2) ? mainSize >> r : 0;

  final shapes = <ConsolationRoundShape>[];
  var survivorsPrev = 0; // S_{r-1}
  var r = 1;
  while (true) {
    final lr = losersFrom(r);
    final entrants = (r == 1) ? directCount + lr : survivorsPrev + lr;
    if (entrants <= 0) {
      // No population at all (e.g. D=0 on a 2-team main bracket): no tree.
      break;
    }
    if (entrants == 1 && lr == 0) {
      // A lone survivor with no fresh feed is already the consolation winner.
      break;
    }
    final padded = _nextPow2(entrants);
    final survivors = padded ~/ 2;
    shapes.add(ConsolationRoundShape(
      round: r,
      entrants: entrants,
      padded: padded,
      byes: padded - entrants,
      survivors: survivors,
      matches: padded ~/ 2,
    ));
    if (survivors <= 1 && losersFrom(r + 1) == 0) break;
    survivorsPrev = survivors;
    r++;
  }
  return ConsolationShape(shapes: shapes);
}

List<int> _standardBracketOrder(int n) {
  if (n == 1) return [1];
  final inner = _standardBracketOrder(n ~/ 2);
  return [
    for (var i = 0; i < inner.length; i++)
      if (i.isEven) ...[inner[i], n + 1 - inner[i]] else ...[
        n + 1 - inner[i],
        inner[i],
      ],
  ];
}

@immutable
final class SingleEliminationBracket extends Bracket {
  const SingleEliminationBracket({required this.rounds});

  final List<BracketRound> rounds;

  @override
  Bracket fill({
    required int round,
    required int position,
    required String participantId,
  }) {
    final newRounds = [...rounds];
    final entry = (seed: 0, participantId: participantId, isBye: false);
    _writeAt(newRounds, round, position, entry, allowThirdPlace: false);
    // Mirror semifinal losers into the third-place playoff (ADR-0017 §4).
    // Trigger only when the FINAL round (last winners round) is being filled
    // — the third-place pairing has just one slot for each semifinal loser.
    final thirdIdx =
        newRounds.indexWhere((r) => r.phase == BracketPhase.thirdPlace);
    final finalsRound = newRounds
        .where((r) => r.phase != BracketPhase.thirdPlace)
        .map((r) => r.number)
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (thirdIdx >= 0 && round == finalsRound && finalsRound > 1) {
      final source = newRounds.firstWhereOrNull(
        (r) => r.number == round - 1 && r.phase != BracketPhase.thirdPlace,
      );
      final pair = source?.pairings.elementAtOrNull(position - 1);
      if (pair != null) {
        final loser = pair.$1.participantId == participantId ? pair.$2 : pair.$1;
        if (loser.participantId != null) {
          _writeAt(newRounds, newRounds[thirdIdx].number, position, loser,
              allowThirdPlace: true);
        }
      }
    }
    return SingleEliminationBracket(rounds: newRounds);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SingleEliminationBracket &&
          const ListEquality<BracketRound>().equals(other.rounds, rounds);

  @override
  int get hashCode => Object.hashAll(rounds);
}

/// Double-elimination bracket (ADR-0027 §1): winner bracket (WB), loser
/// bracket (LB) in the major/minor scheme, grand final (GF) with an optional
/// bracket reset.
///
/// [BracketRound.number] is **phase-local** — WB-R1, LB-R1, GF-R1 are each
/// `number == 1`; disambiguation runs exclusively via `phase`, mirroring the
/// single-elim trick where third-place shares `round_number`/`bracket_position`
/// with the final and is told apart by phase.
@immutable
final class DoubleEliminationBracket extends Bracket {
  const DoubleEliminationBracket({
    required this.wbRounds,
    required this.lbRounds,
    required this.grandFinal,
    required this.grandFinalReset,
    required this.withBracketReset,
  });

  /// WB rounds, number = 1..log2(size), phase == [BracketPhase.wb].
  final List<BracketRound> wbRounds;

  /// LB rounds, number = 1..2*(wbRounds.length-1), phase == [BracketPhase.lb].
  /// Odd number => minor, even number => major (§1.3).
  final List<BracketRound> lbRounds;

  /// Grand final, phase == [BracketPhase.grandFinal], exactly one pairing.
  final BracketRound grandFinal;

  /// Grand-final reset, phase == [BracketPhase.grandFinalReset], one pairing;
  /// `null` when [withBracketReset] is false.
  final BracketRound? grandFinalReset;

  final bool withBracketReset;

  @override
  Bracket fill({
    required int round,
    required int position,
    required String participantId,
  }) {
    // Phase-targeted fill is delegated to the server trigger at runtime
    // (ADR-0027 §1.6); the pure factory only materialises the topology. The
    // single-elim [fill] mirroring has no double-elim analogue here, so we
    // expose the slot write without cross-phase side effects. Filling a WB
    // round delegates to single-elim semantics for that bracket.
    final newWb = [...wbRounds];
    _writeAt(newWb, round, position, _entry(participantId),
        allowThirdPlace: false);
    return DoubleEliminationBracket(
      wbRounds: newWb,
      lbRounds: lbRounds,
      grandFinal: grandFinal,
      grandFinalReset: grandFinalReset,
      withBracketReset: withBracketReset,
    );
  }

  static BracketEntry _entry(String participantId) =>
      (seed: 0, participantId: participantId, isBye: false);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DoubleEliminationBracket &&
          other.withBracketReset == withBracketReset &&
          other.grandFinal == grandFinal &&
          other.grandFinalReset == grandFinalReset &&
          const ListEquality<BracketRound>().equals(other.wbRounds, wbRounds) &&
          const ListEquality<BracketRound>().equals(other.lbRounds, lbRounds);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(wbRounds),
        Object.hashAll(lbRounds),
        grandFinal,
        grandFinalReset,
        withBracketReset,
      );
}

/// Consolation (Trostturnier, Model B) bracket (ADR-0028).
///
/// A separate single-elimination tree that collects the staggered early
/// main-bracket losers plus optional direct starters and plays out the back
/// places (5+). There is NO grand-final merge back into the main bracket
/// (§1.2) — the consolation winner takes place 5, never the title.
///
/// [BracketRound.number] is **phase-local** (consolation R1 == `number == 1`);
/// disambiguation runs exclusively via `phase`. The consolation 3rd-place
/// playoff carries its OWN phase [BracketPhase.consolationThirdPlace] rather
/// than [BracketPhase.thirdPlace], because `consRounds` may equal `mainRounds`
/// and `(third_place, round_number)` would then collide (§7.2).
@immutable
final class ConsolationBracket extends Bracket {
  const ConsolationBracket({required this.rounds, required this.thirdPlace});

  /// Consolation rounds, number = 1..consRounds, phase ==
  /// [BracketPhase.consolation]. The last round is the consolation final
  /// (places 5/6).
  final List<BracketRound> rounds;

  /// Consolation 3rd-place playoff (places 7/8), phase ==
  /// [BracketPhase.consolationThirdPlace]; `null` when the tree is too small
  /// to have a consolation semifinal.
  final BracketRound? thirdPlace;

  @override
  Bracket fill({
    required int round,
    required int position,
    required String participantId,
  }) {
    // Phase-targeted fill is delegated to the server trigger at runtime
    // (ADR-0028 §7.4); the pure factory only materialises the topology. We
    // expose the slot write into the consolation rounds without cross-phase
    // side effects.
    final newRounds = [...rounds];
    _writeAt(newRounds, round, position,
        (seed: 0, participantId: participantId, isBye: false),
        allowThirdPlace: false);
    return ConsolationBracket(rounds: newRounds, thirdPlace: thirdPlace);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConsolationBracket &&
          other.thirdPlace == thirdPlace &&
          const ListEquality<BracketRound>().equals(other.rounds, rounds);

  @override
  int get hashCode => Object.hash(Object.hashAll(rounds), thirdPlace);
}

/// One KO-match row as observed by the mapper.
///
/// Pure-Dart input record for [bracketFromMatches]. The Supabase wire
/// shape carries `phase`, `bracket_position`, `winner_participant`; the
/// adapter (M2.3 wire-package) converts those into this record without
/// pulling Flutter or `supabase_flutter` into the domain.
///
/// `roundNumber` is 1-based. `bracketPosition` is the 1-based pairing
/// index inside the round (not the slot index). `participantA`/`B` may
/// be `null` when the slot is still empty (placeholder for the trigger
/// to fill once the feeding match finalizes).
typedef KoMatchRow = ({
  int roundNumber,
  int bracketPosition,
  BracketPhase phase,
  String? participantA,
  String? participantB,
  String? winnerParticipantId,
  bool isBye,
});

/// Pure mapper: rebuild a [Bracket] from DB-match rows.
///
/// The mapper is **passive** — it never auto-advances winners into
/// follow-up matches. Filling follow-up slots is the server trigger's
/// responsibility (see ADR-0017 §5 and TASK-M2.2-T4). The mapper just
/// reflects whatever the DB currently holds.
///
/// Throws [ArgumentError] when [matches] is empty.
Bracket bracketFromMatches(List<KoMatchRow> matches) {
  if (matches.isEmpty) {
    throw ArgumentError.value(matches, 'matches', 'is empty');
  }
  final hasDouble = matches.any((m) =>
      m.phase == BracketPhase.wb ||
      m.phase == BracketPhase.lb ||
      m.phase == BracketPhase.grandFinal ||
      m.phase == BracketPhase.grandFinalReset);
  if (hasDouble) return _doubleEliminationFromMatches(matches);
  final hasConsolation = matches.any((m) =>
      m.phase == BracketPhase.consolation ||
      m.phase == BracketPhase.consolationThirdPlace);
  if (hasConsolation) return _consolationFromMatches(matches); // ADR-0028 §7.3
  final winners = matches.where((m) => m.phase != BracketPhase.thirdPlace);
  final thirdPlace =
      matches.where((m) => m.phase == BracketPhase.thirdPlace).toList();
  final byRound = <int, List<KoMatchRow>>{};
  for (final m in winners) {
    byRound.putIfAbsent(m.roundNumber, () => <KoMatchRow>[]).add(m);
  }
  final totalRounds =
      byRound.keys.isEmpty ? 0 : byRound.keys.reduce((a, b) => a > b ? a : b);
  final rounds = <BracketRound>[
    for (var r = 1; r <= totalRounds; r++)
      BracketRound(
        number: r,
        phase:
            r == totalRounds ? BracketPhase.finals : BracketPhase.winners,
        pairings: _pairingsForRound(byRound[r] ?? const <KoMatchRow>[]),
      ),
    if (thirdPlace.isNotEmpty)
      BracketRound(
        number: totalRounds,
        phase: BracketPhase.thirdPlace,
        pairings: _pairingsForRound(thirdPlace),
      ),
  ];
  return SingleEliminationBracket(rounds: rounds);
}

List<BracketPairing> _pairingsForRound(List<KoMatchRow> rows) {
  if (rows.isEmpty) return const <BracketPairing>[];
  final sorted = [...rows]
    ..sort((a, b) => a.bracketPosition.compareTo(b.bracketPosition));
  return [
    for (final m in sorted)
      (
        (seed: 0, participantId: m.participantA, isBye: m.isBye),
        (seed: 0, participantId: m.participantB, isBye: m.isBye),
      ),
  ];
}

/// Rebuild a [DoubleEliminationBracket] from DB-match rows (ADR-0027 §1.9).
///
/// Rows are grouped by `phase` and then `roundNumber`; pairings reuse the
/// existing [_pairingsForRound] helper. Like the single-elim path the mapper is
/// **passive** — it reflects only the DB state and never writes follow-up slots.
Bracket _doubleEliminationFromMatches(List<KoMatchRow> matches) {
  List<BracketRound> roundsFor(BracketPhase phase) {
    final byRound = <int, List<KoMatchRow>>{};
    for (final m in matches.where((m) => m.phase == phase)) {
      byRound.putIfAbsent(m.roundNumber, () => <KoMatchRow>[]).add(m);
    }
    final numbers = byRound.keys.toList()..sort();
    return [
      for (final r in numbers)
        BracketRound(
          number: r,
          phase: phase,
          pairings: _pairingsForRound(byRound[r]!),
        ),
    ];
  }

  final gfRounds = roundsFor(BracketPhase.grandFinal);
  final resetRounds = roundsFor(BracketPhase.grandFinalReset);
  const placeholder = (seed: 0, participantId: null, isBye: false);
  const emptyGf = BracketRound(
    number: 1,
    phase: BracketPhase.grandFinal,
    pairings: [(placeholder, placeholder)],
  );
  return DoubleEliminationBracket(
    wbRounds: roundsFor(BracketPhase.wb),
    lbRounds: roundsFor(BracketPhase.lb),
    grandFinal: gfRounds.isEmpty ? emptyGf : gfRounds.first,
    grandFinalReset: resetRounds.isEmpty ? null : resetRounds.first,
    withBracketReset: resetRounds.isNotEmpty,
  );
}

/// Rebuild a [ConsolationBracket] from DB-match rows (ADR-0028 §7.3).
///
/// Groups the `consolation` rows by phase-local `round_number` into the
/// consolation rounds and projects the single `consolation_third_place` row
/// into the playoff. Reuses the existing [_pairingsForRound] helper. Like the
/// single-/double-elim paths the mapper is **passive** — it reflects only the
/// DB state and never writes follow-up slots. Disambiguation is solely via
/// `phase` (no extra column).
Bracket _consolationFromMatches(List<KoMatchRow> matches) {
  final byRound = <int, List<KoMatchRow>>{};
  for (final m in matches.where((m) => m.phase == BracketPhase.consolation)) {
    byRound.putIfAbsent(m.roundNumber, () => <KoMatchRow>[]).add(m);
  }
  final numbers = byRound.keys.toList()..sort();
  final rounds = <BracketRound>[
    for (final r in numbers)
      BracketRound(
        number: r,
        phase: BracketPhase.consolation,
        pairings: _pairingsForRound(byRound[r]!),
      ),
  ];
  final thirdRows = matches
      .where((m) => m.phase == BracketPhase.consolationThirdPlace)
      .toList();
  final thirdPlace = thirdRows.isEmpty
      ? null
      : BracketRound(
          number: 1,
          phase: BracketPhase.consolationThirdPlace,
          pairings: _pairingsForRound(thirdRows),
        );
  return ConsolationBracket(rounds: rounds, thirdPlace: thirdPlace);
}

void _writeAt(
  List<BracketRound> rounds,
  int roundNumber,
  int position,
  BracketEntry entry, {
  required bool allowThirdPlace,
}) {
  if (position < 1) {
    throw ArgumentError.value(position, 'position', 'must be >= 1');
  }
  final idx = rounds.indexWhere((r) =>
      r.number == roundNumber &&
      (allowThirdPlace
          ? r.phase == BracketPhase.thirdPlace
          : r.phase != BracketPhase.thirdPlace));
  if (idx < 0) {
    throw ArgumentError.value(roundNumber, 'round', 'no matching round');
  }
  final target = rounds[idx];
  final pairIdx = (position - 1) ~/ 2;
  final slotIdx = (position - 1) % 2;
  if (pairIdx >= target.pairings.length) {
    throw ArgumentError.value(position, 'position', 'out of range');
  }
  final newPairings = [...target.pairings];
  final cur = newPairings[pairIdx];
  newPairings[pairIdx] = (slotIdx == 0 ? entry : cur.$1, slotIdx == 1 ? entry : cur.$2);
  rounds[idx] = BracketRound(
    number: target.number,
    phase: target.phase,
    pairings: newPairings,
  );
}
