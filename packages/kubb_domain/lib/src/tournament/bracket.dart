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
  grandFinalReset // GF game 2 (only materialised when with_bracket_reset)
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
