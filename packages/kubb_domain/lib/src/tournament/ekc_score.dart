import 'package:kubb_domain/src/tournament/king_outcome.dart';
import 'package:meta/meta.dart';

/// Who won a single set.
///
/// M2a: the [none] variant is the canonical representation of "no set
/// winner" — a set that ended without a decisive side. It exists so the
/// group phase can record "Keiner" (no king) WITHOUT forcing an
/// artificial A/B winner via kubb-majority. A [none] set is neither a
/// win for A nor for B (see [MatchEkcScore.setsWonA] / `setsWonB`) and
/// adds no winner-bonus to the EKC tally.
enum SetWinner { teamA, teamB, none }

/// The phase a tournament match belongs to, for the canonical set-winner
/// derivation. Group/pool play allows non-decisive sets; the knockout
/// phase ultimately needs a decisive winner (resolved client-side via the
/// finisher prompt in M2b — never via an auto kubb-majority fallback here).
enum MatchPhase { group, ko }

/// Maps the DB `tournament_matches.phase` wire token to [MatchPhase].
/// Only `'group'` is the group/pool phase; every bracket phase
/// (`ko` / `final` / `third_place` / `wb` / `lb` / `grand_final` /
/// `grand_final_reset` / `consolation` / `consolation_third_place`) is
/// treated as the KO phase for the canonical set-winner derivation.
/// `null` / unknown defaults to [MatchPhase.group] — the non-forcing
/// default, so an absent column never fabricates a KO auto-winner.
MatchPhase matchPhaseFromWire(String? wire) =>
    wire == 'group' || wire == null ? MatchPhase.group : MatchPhase.ko;

/// How a match's per-set score is interpreted for the canonical winner
/// derivation. Mirrors the server's `tournaments.scoring`
/// (`classic` / `ekc`). Defined locally in the domain so the pure
/// derivation has no dependency on the higher-level `TournamentScoring`
/// port enum (callers map one to the other).
enum SetScoring { classic, ekc }

/// Canonical, deterministic derivation of a set's [SetWinner] from the
/// raw inputs, identical on client and server (M2a). This is the single
/// source of truth that makes "same reality == agreement" hold in the
/// consensus engine.
///
/// Rules:
///   * King fell on a side ([KingHitBy]) -> that side wins the set.
///   * No king ([KingMissed] / [KingTimedOut]):
///       - GROUP phase, classic scoring  -> [SetWinner.none] (no forced
///         winner; the standing stays, e.g. 1:1).
///       - GROUP phase, EKC scoring      -> winner by base-kubbs; equal
///         kubbs -> [SetWinner.none] (draw allowed).
///       - KO phase                      -> NO auto kubb-majority fallback.
///         The decisive winner comes from the client finisher prompt
///         (M2b); here we keep the status quo as [SetWinner.none].
SetWinner resolveSetWinner({
  required KingOutcome kingOutcome,
  required int basekubbsA,
  required int basekubbsB,
  required MatchPhase phase,
  required SetScoring scoring,
}) {
  // King fell -> that side wins, regardless of phase or scoring mode.
  if (kingOutcome is KingHitBy) {
    // The participant id behind the KingHitBy is the scoring side; the
    // caller resolves which match side it belongs to and passes the
    // outcome accordingly. We cannot map participant->side here without
    // the pairing, so the king-side decision is expressed by the caller
    // via the dedicated [resolveSetWinnerForSide] overload below.
    // Defensive fallback keeps the pure signature usable in tests.
    return SetWinner.none;
  }

  // No king. Phase- and scoring-dependent.
  switch (phase) {
    case MatchPhase.group:
      switch (scoring) {
        case SetScoring.classic:
          // Classic group set with no king -> not a won set.
          return SetWinner.none;
        case SetScoring.ekc:
          // EKC group set -> result by base-kubbs, draw allowed.
          if (basekubbsA > basekubbsB) return SetWinner.teamA;
          if (basekubbsB > basekubbsA) return SetWinner.teamB;
          return SetWinner.none;
      }
    case MatchPhase.ko:
      // KO winner is supplied by the finisher prompt (M2b). No auto
      // kubb-majority fallback: keep the set non-decisive here.
      return SetWinner.none;
  }
}

/// Variant of [resolveSetWinner] that already knows which match side the
/// king fell for. `kingSide` is the resolved [SetWinner.teamA] /
/// [SetWinner.teamB] when the king fell, or `null` when no king fell.
/// Used by call sites (client + the server mirror) that have the pairing
/// available and have mapped the [KingHitBy] participant to a side.
SetWinner resolveSetWinnerForSide({
  required SetWinner? kingSide,
  required int basekubbsA,
  required int basekubbsB,
  required MatchPhase phase,
  required SetScoring scoring,
}) {
  if (kingSide == SetWinner.teamA || kingSide == SetWinner.teamB) {
    return kingSide!;
  }
  switch (phase) {
    case MatchPhase.group:
      switch (scoring) {
        case SetScoring.classic:
          return SetWinner.none;
        case SetScoring.ekc:
          if (basekubbsA > basekubbsB) return SetWinner.teamA;
          if (basekubbsB > basekubbsA) return SetWinner.teamB;
          return SetWinner.none;
      }
    case MatchPhase.ko:
      return SetWinner.none;
  }
}

@immutable
class SetScore {
  SetScore({
    required this.basekubbsKnockedByA,
    required this.basekubbsKnockedByB,
    required this.winner,
    this.kingOutcome = const KingMissed(),
  }) {
    if (basekubbsKnockedByA < 0 || basekubbsKnockedByB < 0) {
      throw ArgumentError('basekubb counts must be non-negative');
    }
  }

  final int basekubbsKnockedByA;
  final int basekubbsKnockedByB;
  final SetWinner winner;

  /// Per R11-F-01: how the King was dealt with in this set. Defaults to
  /// [KingMissed] — the historical implicit behaviour, where the set ends
  /// on a regular win without crediting any king-points.
  final KingOutcome kingOutcome;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetScore &&
          other.basekubbsKnockedByA == basekubbsKnockedByA &&
          other.basekubbsKnockedByB == basekubbsKnockedByB &&
          other.winner == winner &&
          other.kingOutcome == kingOutcome;

  @override
  int get hashCode => Object.hash(
        basekubbsKnockedByA,
        basekubbsKnockedByB,
        winner,
        kingOutcome,
      );
}

/// Per R11-F-01: the EKC contribution of one set, decomposed into the
/// per-team points for A and B. A [KingTimedOut] outcome short-circuits
/// the set to a 0:0 contribution; otherwise basekubbs + 3-point winner
/// bonus apply, plus a single +1 king-point for the set winner on
/// [KingHitBy].
({int pointsA, int pointsB}) _setContribution(SetScore set) {
  return switch (set.kingOutcome) {
    KingTimedOut() => (pointsA: 0, pointsB: 0),
    KingHitBy() || KingMissed() => () {
        final winnerBonusA = set.winner == SetWinner.teamA ? 3 : 0;
        final winnerBonusB = set.winner == SetWinner.teamB ? 3 : 0;
        final kingBonusA = set.kingOutcome is KingHitBy &&
                set.winner == SetWinner.teamA
            ? 1
            : 0;
        final kingBonusB = set.kingOutcome is KingHitBy &&
                set.winner == SetWinner.teamB
            ? 1
            : 0;
        return (
          pointsA: set.basekubbsKnockedByA + winnerBonusA + kingBonusA,
          pointsB: set.basekubbsKnockedByB + winnerBonusB + kingBonusB,
        );
      }(),
  };
}

@immutable
class MatchEkcScore {
  MatchEkcScore(List<SetScore> sets)
      : sets = List<SetScore>.unmodifiable(sets),
        pointsForA = sets.fold<int>(
          0,
          (acc, s) => acc + _setContribution(s).pointsA,
        ),
        pointsForB = sets.fold<int>(
          0,
          (acc, s) => acc + _setContribution(s).pointsB,
        ),
        setsWonA = sets.where((s) => s.winner == SetWinner.teamA).length,
        setsWonB = sets.where((s) => s.winner == SetWinner.teamB).length;

  final List<SetScore> sets;
  final int pointsForA;
  final int pointsForB;
  final int setsWonA;
  final int setsWonB;

  SetWinner? get matchWinner {
    if (setsWonA == setsWonB) return null;
    return setsWonA > setsWonB ? SetWinner.teamA : SetWinner.teamB;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchEkcScore &&
          other.sets.length == sets.length &&
          _listEquals(other.sets, sets);

  @override
  int get hashCode => Object.hashAll(sets);

  static bool _listEquals(List<SetScore> a, List<SetScore> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

MatchEkcScore computeEkc(List<SetScore> sets) => MatchEkcScore(sets);
