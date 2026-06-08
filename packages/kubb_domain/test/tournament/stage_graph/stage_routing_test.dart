import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

/// Convenience builder for a [StageRankingEntry].
StageRankingEntry _e(String id, int rank, [int? koRound]) =>
    StageRankingEntry(participantId: id, rank: rank, koEliminationRound: koRound);

/// Builds an edge carrying [selector] (node ids are irrelevant to routing).
StageEdge _edge(EdgeSelector selector) =>
    StageEdge(fromNodeId: 'src', selector: selector, toNodeId: 'dst');

/// Extracts the `selected` list for the edge at [index] of a routing result.
List<String> _selected(
  List<({StageEdge edge, List<String> selected})> result,
  int index,
) =>
    result[index].selected;

void main() {
  group('routeStageOutputs', () {
    test('T1 — 8-entry ranking, mixed selectors', () {
      // Ranks 1..8; r3 lost in KO round 1, r5 in round 1, r7 in round 2.
      final ranking = [
        _e('r1', 1),
        _e('r2', 2),
        _e('r3', 3, 1),
        _e('r4', 4),
        _e('r5', 5, 1),
        _e('r6', 6),
        _e('r7', 7, 2),
        _e('r8', 8),
      ];
      final edges = [
        _edge(const TopK(2)),
        _edge(const Ranks(3, 4)),
        _edge(LosersOfRounds(const {1})),
        _edge(const Winners()),
        _edge(const NonQualifiers()),
      ];

      final result = routeStageOutputs(
        outgoingEdges: edges,
        ranking: ranking,
      );

      // Output order mirrors edge order, 1:1.
      expect(result.length, edges.length);
      expect([for (final r in result) r.edge], edges);

      expect(_selected(result, 0), ['r1', 'r2']);
      expect(_selected(result, 1), ['r3', 'r4']);
      expect(_selected(result, 2), ['r3', 'r5']);
      expect(_selected(result, 3), ['r1']);
      // Non-NQ union: {r1,r2,r3,r4,r5}. Leftover in ranking order:
      expect(_selected(result, 4), ['r6', 'r7', 'r8']);
    });

    test('T2 — NonQualifiers alone yields the whole ranking', () {
      final ranking = [_e('a', 1), _e('b', 2), _e('c', 3)];
      final result = routeStageOutputs(
        outgoingEdges: [_edge(const NonQualifiers())],
        ranking: ranking,
      );
      expect(_selected(result, 0), ['a', 'b', 'c']);
    });

    test('T3 — NonQualifiers + TopK(2) yields ranking minus top 2', () {
      final ranking = [_e('a', 1), _e('b', 2), _e('c', 3), _e('d', 4)];
      final result = routeStageOutputs(
        outgoingEdges: [_edge(const TopK(2)), _edge(const NonQualifiers())],
        ranking: ranking,
      );
      expect(_selected(result, 0), ['a', 'b']);
      expect(_selected(result, 1), ['c', 'd']);
    });

    test('T4 — determinism: same input -> identical output (incl. tie-break)',
        () {
      // Two entries share rank 1 to exercise the participantId tie-break.
      final ranking = [
        _e('zeta', 1),
        _e('alpha', 1),
        _e('m', 2),
      ];
      final edges = [
        _edge(const Winners()),
        _edge(const NonQualifiers()),
      ];

      final first = routeStageOutputs(outgoingEdges: edges, ranking: ranking);
      final second = routeStageOutputs(outgoingEdges: edges, ranking: ranking);

      expect(first.length, second.length);
      for (var i = 0; i < first.length; i++) {
        expect(first[i].edge, second[i].edge);
        expect(first[i].selected, second[i].selected);
      }
      // Tie-break: alpha before zeta among the two rank-1 winners.
      expect(_selected(first, 0), ['alpha', 'zeta']);
      expect(_selected(first, 1), ['m']);
    });

    test('T5 — duplicate participantId throws ArgumentError', () {
      expect(
        () => routeStageOutputs(
          outgoingEdges: [_edge(const TopK(1))],
          ranking: [_e('a', 1), _e('a', 2)],
        ),
        throwsArgumentError,
      );
    });

    test('T6 — invalid Ranks(3, 2) throws ArgumentError', () {
      expect(
        () => routeStageOutputs(
          outgoingEdges: [_edge(const Ranks(3, 2))],
          ranking: [_e('a', 1), _e('b', 2), _e('c', 3)],
        ),
        throwsArgumentError,
      );
    });

    test('T7 — LosersOfRounds is round-precise', () {
      final ranking = [
        _e('champ', 1), // null koEliminationRound
        _e('r1loser', 2, 1),
        _e('r2loser', 3, 2),
        _e('r2other', 4, 2),
      ];
      final result = routeStageOutputs(
        outgoingEdges: [_edge(LosersOfRounds(const {2}))],
        ranking: ranking,
      );
      expect(_selected(result, 0), ['r2loser', 'r2other']);
    });

    test('T8 — TopK boundary cases', () {
      final ranking = [_e('a', 1), _e('b', 2), _e('c', 3)];
      // TopK(0) -> empty.
      expect(
        _selected(
          routeStageOutputs(
            outgoingEdges: [_edge(const TopK(0))],
            ranking: ranking,
          ),
          0,
        ),
        isEmpty,
      );
      // TopK(k) with k > count -> all entries, no throw.
      expect(
        _selected(
          routeStageOutputs(
            outgoingEdges: [_edge(const TopK(99))],
            ranking: ranking,
          ),
          0,
        ),
        ['a', 'b', 'c'],
      );
    });

    test('T9 — Ranks is inclusive on both ends', () {
      final ranking = [
        _e('a', 1),
        _e('b', 2),
        _e('c', 3),
        _e('d', 4),
      ];
      final result = routeStageOutputs(
        outgoingEdges: [_edge(const Ranks(2, 3))],
        ranking: ranking,
      );
      expect(_selected(result, 0), ['b', 'c']);
    });

    test('T10 — multiple NonQualifiers edges yield the same leftover', () {
      final ranking = [_e('a', 1), _e('b', 2), _e('c', 3), _e('d', 4)];
      final edges = [
        _edge(const NonQualifiers()),
        _edge(const TopK(2)),
        _edge(const NonQualifiers()),
      ];
      final result = routeStageOutputs(outgoingEdges: edges, ranking: ranking);

      // Both NQ edges appear at their input position with the identical rest.
      expect(_selected(result, 0), ['c', 'd']);
      expect(_selected(result, 1), ['a', 'b']);
      expect(_selected(result, 2), ['c', 'd']);
    });

    test('T11 — overlapping non-NQ selectors collapse to one union', () {
      final ranking = [
        _e('a', 1),
        _e('b', 2),
        _e('c', 3),
        _e('d', 4),
        _e('e', 5),
      ];
      final edges = [
        _edge(const TopK(3)), // a, b, c
        _edge(const Ranks(2, 4)), // b, c, d
        _edge(const NonQualifiers()),
      ];
      final result = routeStageOutputs(outgoingEdges: edges, ranking: ranking);

      expect(_selected(result, 0), ['a', 'b', 'c']);
      expect(_selected(result, 1), ['b', 'c', 'd']);
      // Union {a,b,c,d}; leftover = {e}.
      expect(_selected(result, 2), ['e']);
    });

    test('T12 — empty inputs', () {
      // No edges -> empty result.
      expect(
        routeStageOutputs(
          outgoingEdges: [],
          ranking: [_e('a', 1)],
        ),
        isEmpty,
      );
      // Empty ranking -> empty selected per edge (NonQualifiers -> empty).
      final result = routeStageOutputs(
        outgoingEdges: [_edge(const TopK(2)), _edge(const NonQualifiers())],
        ranking: [],
      );
      expect(_selected(result, 0), isEmpty);
      expect(_selected(result, 1), isEmpty);
    });

    test('T13 — negative selector / rank validation', () {
      expect(
        () => routeStageOutputs(
          outgoingEdges: [_edge(const TopK(-1))],
          ranking: [_e('a', 1)],
        ),
        throwsArgumentError,
      );
      expect(
        () => routeStageOutputs(
          outgoingEdges: [_edge(const Ranks(0, 4))],
          ranking: [_e('a', 1)],
        ),
        throwsArgumentError,
      );
      expect(
        () => routeStageOutputs(
          outgoingEdges: [_edge(const NonQualifiers())],
          ranking: [_e('a', 0)],
        ),
        throwsArgumentError,
      );
    });

    test('T14 — selected list is rank asc, then participantId tie-break', () {
      // Provided out of order; two share rank 2.
      final ranking = [
        _e('d', 3),
        _e('b', 2),
        _e('a', 2),
        _e('c', 1),
      ];
      final result = routeStageOutputs(
        outgoingEdges: [_edge(const Ranks(1, 3))],
        ranking: ranking,
      );
      expect(_selected(result, 0), ['c', 'a', 'b', 'd']);
    });

    test('T16 — Winners returns multiple rank-1 entries; excluded from NQ', () {
      final ranking = [
        _e('x', 1),
        _e('y', 1),
        _e('z', 2),
      ];
      final result = routeStageOutputs(
        outgoingEdges: [_edge(const Winners()), _edge(const NonQualifiers())],
        ranking: ranking,
      );
      expect(_selected(result, 0), ['x', 'y']);
      expect(_selected(result, 1), ['z']);
    });

    test('does not mutate the input ranking list', () {
      final ranking = [_e('b', 2), _e('a', 1)];
      final snapshot = [...ranking];
      routeStageOutputs(
        outgoingEdges: [_edge(const TopK(1))],
        ranking: ranking,
      );
      expect(ranking, snapshot);
    });
  });

  group('StageRankingEntry value semantics', () {
    test('T15 — equality and hashCode over all three fields', () {
      const a = StageRankingEntry(
        participantId: 'p',
        rank: 1,
        koEliminationRound: 2,
      );
      const b = StageRankingEntry(
        participantId: 'p',
        rank: 1,
        koEliminationRound: 2,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      // Differ in participantId.
      expect(
        a == const StageRankingEntry(participantId: 'q', rank: 1, koEliminationRound: 2),
        isFalse,
      );
      // Differ in rank.
      expect(
        a == const StageRankingEntry(participantId: 'p', rank: 2, koEliminationRound: 2),
        isFalse,
      );
      // Differ in koEliminationRound (null vs set).
      expect(
        a == const StageRankingEntry(participantId: 'p', rank: 1),
        isFalse,
      );
    });

    test('constructor performs no validation (rank < 1 allowed)', () {
      const entry = StageRankingEntry(participantId: 'p', rank: 0);
      expect(entry.rank, 0);
    });

    test('toString includes all fields', () {
      const entry = StageRankingEntry(
        participantId: 'p',
        rank: 1,
        koEliminationRound: 3,
      );
      expect(entry.toString(), contains('p'));
      expect(entry.toString(), contains('1'));
      expect(entry.toString(), contains('3'));
    });
  });
}
