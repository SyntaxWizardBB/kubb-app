import 'package:kubb_domain/src/tournament/stage_graph/edge_selector.dart';
import 'package:kubb_domain/src/tournament/stage_graph/stage_edge.dart';
import 'package:meta/meta.dart';

/// One participant's final standing within a COMPLETED stage.
///
/// Pure data: this type performs NO validation in its constructor. The
/// consistency of a whole ranking (no duplicate ids, `rank >= 1`, ...) is
/// checked by [routeStageOutputs], not per entry, so tests must not expect the
/// constructor to throw.
@immutable
class StageRankingEntry {
  /// Creates a ranking entry.
  ///
  /// [koEliminationRound] is the knockout round in which the participant was
  /// eliminated; it is `null` for the champion and for non-KO stages.
  const StageRankingEntry({
    required this.participantId,
    required this.rank,
    this.koEliminationRound,
  });

  /// Stable identifier of the participant.
  final String participantId;

  /// 1-based final rank within the stage (stage-internal, final).
  final int rank;

  /// KO stages: the round the participant was eliminated in; `null` for the
  /// champion and for non-KO stages.
  final int? koEliminationRound;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StageRankingEntry &&
          other.participantId == participantId &&
          other.rank == rank &&
          other.koEliminationRound == koEliminationRound;

  @override
  int get hashCode => Object.hash(participantId, rank, koEliminationRound);

  @override
  String toString() => 'StageRankingEntry(participantId: $participantId, '
      'rank: $rank, koEliminationRound: $koEliminationRound)';
}

/// Evaluates ALL outgoing edges of a completed stage against its [ranking],
/// returning the selected participantIds per edge (in ranking order).
///
/// This is the pure routing core of ADR-0030 §Runner-Semantik step 2: it
/// "applies the selectors to the local ordering". It does NOT detect stage
/// completion (step 1), nor materialize/seed into target stages (step 3). It
/// works purely on `rank` / `koEliminationRound` and makes no assumption about
/// node types.
///
/// Selector semantics (ADR-0030 §Edge):
///   * `TopK(k)`            -> entries with rank in `1..k`
///   * `Ranks(from, to)`    -> entries with rank in `from..to` (inclusive)
///   * `LosersOfRounds(rs)` -> entries whose `koEliminationRound` is in `rs`
///                             (`koEliminationRound == null` is never matched)
///   * `Winners`            -> entries with `rank == 1` (possibly several)
///   * `NonQualifiers`      -> the leftover: every entry NOT selected by ANY
///                             non-`NonQualifiers` edge of this stage, in
///                             ranking order
///
/// Two-phase evaluation: all non-`NonQualifiers` edges are resolved first; the
/// `NonQualifiers` leftover is then `{all ranking ids} \ {union of ids actually
/// selected by non-NQ edges}`. The union is built over the concretely selected
/// ids, so overlapping non-NQ selectors collapse into one set. A `NonQualifiers`
/// edge never restricts the leftover of another `NonQualifiers` edge, so MULTIPLE
/// `NonQualifiers` edges are allowed and each yields the SAME leftover.
///
/// Output order equals the input order of [outgoingEdges] (stable, 1:1, same
/// length; each edge appears exactly once even for duplicate selectors). Each
/// `selected` list is in ranking order: `rank` ascending, tie-broken by
/// `participantId` (lexicographic), and contains only participantIds, without
/// duplicates.
///
/// Determinism: identical input yields bit-identical output; there is no
/// dependence on `Set`/`Map` iteration order in the observable result.
///
/// Throws [ArgumentError] when [ranking] contains a duplicate `participantId`,
/// when any `rank < 1`, when a `TopK.k < 0`, or when a `Ranks` band is invalid
/// (`from < 1` or `from > to`). Empty inputs are not errors: empty
/// [outgoingEdges] yields `[]`; empty [ranking] yields an empty `selected` list
/// per edge.
List<({StageEdge edge, List<String> selected})> routeStageOutputs({
  required List<StageEdge> outgoingEdges,
  required List<StageRankingEntry> ranking,
}) {
  // Validate the ranking once: unique ids, every rank >= 1.
  final seenIds = <String>{};
  for (final entry in ranking) {
    if (entry.rank < 1) {
      throw ArgumentError.value(
        entry.rank,
        'ranking',
        'rank must be >= 1 (participantId: ${entry.participantId})',
      );
    }
    if (!seenIds.add(entry.participantId)) {
      throw ArgumentError.value(
        entry.participantId,
        'ranking',
        'duplicate participantId in ranking',
      );
    }
  }

  // Stable ranking order: rank ascending, then participantId lexicographic.
  // This total order is the single source of truth for every emitted list.
  final orderedRanking = [...ranking]..sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      return a.participantId.compareTo(b.participantId);
    });

  // Phase 1: resolve every non-NonQualifiers edge and remember, per edge, the
  // selected ids in ranking order. Also accumulate the union of all ids that
  // any non-NQ edge selected (the qualifiers).
  final selectionPerEdge = <int, List<String>>{};
  final qualifiedIds = <String>{};

  for (var i = 0; i < outgoingEdges.length; i++) {
    final selector = outgoingEdges[i].selector;
    if (selector is NonQualifiers) {
      // Resolved in phase 2; it must not count itself as a selecting edge.
      continue;
    }
    final selected = _selectFor(selector, orderedRanking);
    selectionPerEdge[i] = selected;
    qualifiedIds.addAll(selected);
  }

  // Phase 2: the NonQualifiers leftover = ranking minus the qualifiers union,
  // in ranking order. Every NonQualifiers edge yields this same leftover.
  final leftover = [
    for (final entry in orderedRanking)
      if (!qualifiedIds.contains(entry.participantId)) entry.participantId,
  ];

  return [
    for (var i = 0; i < outgoingEdges.length; i++)
      (
        edge: outgoingEdges[i],
        selected: outgoingEdges[i].selector is NonQualifiers
            ? List<String>.of(leftover)
            : selectionPerEdge[i]!,
      ),
  ];
}

/// Resolves a single non-[NonQualifiers] selector against the already
/// ranking-ordered [orderedRanking], returning the matched participantIds in
/// that same order, without duplicates.
List<String> _selectFor(
  EdgeSelector selector,
  List<StageRankingEntry> orderedRanking,
) {
  switch (selector) {
    case TopK(:final k):
      if (k < 0) {
        throw ArgumentError.value(k, 'selector', 'TopK.k must be >= 0');
      }
      // ranking ranks are already validated to be >= 1, so `rank <= k` suffices.
      return [
        for (final e in orderedRanking)
          if (e.rank <= k) e.participantId,
      ];
    case Ranks(:final from, :final to):
      if (from < 1 || from > to) {
        throw ArgumentError.value(
          selector,
          'selector',
          'Ranks requires from >= 1 and from <= to',
        );
      }
      return [
        for (final e in orderedRanking)
          if (e.rank >= from && e.rank <= to) e.participantId,
      ];
    case LosersOfRounds(:final rounds):
      return [
        for (final e in orderedRanking)
          if (e.koEliminationRound != null &&
              rounds.contains(e.koEliminationRound))
            e.participantId,
      ];
    case Winners():
      return [
        for (final e in orderedRanking)
          if (e.rank == 1) e.participantId,
      ];
    case NonQualifiers():
      // Handled in phase 2 of routeStageOutputs; never reached here.
      throw StateError('NonQualifiers must be resolved as the leftover');
  }
}
