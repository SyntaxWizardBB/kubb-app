import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

const _r1 = MatchFormatSpec(setsToWin: 2, maxSets: 3, timeLimitSeconds: 600);
const _r2 = MatchFormatSpec(setsToWin: 2, maxSets: 3, timeLimitSeconds: 720);
const _r3 = MatchFormatSpec(
  setsToWin: 3,
  maxSets: 5,
  timeLimitSeconds: 900,
  finalNoTiebreak: true,
);

/// A non-trivial KO graph: three rounds (4 → 2 → 1 fields), winner edges wiring
/// each round into the next, plus one loser edge feeding a consolation field
/// and one deliberately open winner slot. Every round carries its own match
/// format and KO tiebreak, so the summary has to surface eight fields, three
/// distinct formats and three tiebreaks without dropping any.
StageTypeGraph _koGraph() => StageTypeGraph(
      category: TypeStageCategory.ko,
      rounds: [
        TypeRound(
          roundNumber: 1,
          fields: const [
            TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
            TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
            TypeField(id: 'R1F3', roundNumber: 1, slot: 3),
            TypeField(id: 'R1F4', roundNumber: 1, slot: 4),
          ],
          matchFormat: _r1,
          koMatchup: KoMatchup.seedHighVsLow,
          koTiebreak: KoTiebreakMethod.classicKingtossRemoval,
        ),
        TypeRound(
          roundNumber: 2,
          fields: const [
            TypeField(id: 'R2F1', roundNumber: 2, slot: 1),
            TypeField(id: 'R2F2', roundNumber: 2, slot: 2),
          ],
          matchFormat: _r2,
          koMatchup: KoMatchup.oneVsTwo,
          koTiebreak: KoTiebreakMethod.mightyFinisherShootout,
        ),
        TypeRound(
          roundNumber: 3,
          fields: const [
            TypeField(id: 'R3F1', roundNumber: 3, slot: 1),
          ],
          matchFormat: _r3,
          koMatchup: KoMatchup.oneVsTwo,
          koTiebreak: KoTiebreakMethod.classicKingtossRemoval,
        ),
      ],
      edges: const [
        WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'),
        WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'),
        WinnerEdge(fromFieldId: 'R1F3', toFieldId: 'R2F2'),
        WinnerEdge(fromFieldId: 'R1F4', toFieldId: 'R2F2'),
        WinnerEdge(fromFieldId: 'R2F1', toFieldId: 'R3F1'),
        LoserEdge(fromFieldId: 'R2F1', toFieldId: 'R3F1'),
        OpenEdge(fromFieldId: 'R2F2', slot: OpenEdgeSlot.winner),
      ],
    );

/// A Vorrunde graph: two rounds of three plates each, joined by a single
/// advance-all transition with per-round pairing rules.
StageTypeGraph _vorrundeGraph() => StageTypeGraph(
      category: TypeStageCategory.vorrunde,
      rounds: [
        TypeRound(
          roundNumber: 1,
          fields: const [
            TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
            TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
            TypeField(id: 'R1F3', roundNumber: 1, slot: 3),
          ],
          matchFormat: _r1,
          pairingRule: TypePairingRule.groupRoundRobin,
        ),
        TypeRound(
          roundNumber: 2,
          fields: const [
            TypeField(id: 'R2F1', roundNumber: 2, slot: 1),
            TypeField(id: 'R2F2', roundNumber: 2, slot: 2),
            TypeField(id: 'R2F3', roundNumber: 2, slot: 3),
          ],
          matchFormat: _r2,
          pairingRule: TypePairingRule.schochMonrad,
        ),
      ],
      edges: const [AdvanceAllEdge(fromRound: 1, toRound: 2)],
    );

void main() {
  group('summarizeStageTypeGraph completeness', () {
    test('covers every round of a non-trivial KO graph in order', () {
      final graph = _koGraph();
      final summary = summarizeStageTypeGraph(graph);

      expect(
        summary.rounds.map((r) => r.roundNumber),
        graph.rounds.map((r) => r.roundNumber),
        reason: 'every round, same order',
      );
      expect(summary.rounds.length, graph.rounds.length);
    });

    test('covers every field of every round, none dropped', () {
      final graph = _koGraph();
      final summary = summarizeStageTypeGraph(graph);

      final expectedFieldIds = <String>[
        for (final r in graph.rounds)
          for (final f in r.fields) f.id,
      ];
      final summaryFieldIds = <String>[
        for (final r in summary.rounds)
          for (final f in r.fields) f.field.id,
      ];

      expect(summaryFieldIds, expectedFieldIds);
      expect(summary.totalFields, graph.allFields.length);
      expect(summary.totalFields, 7);

      // Per-round field counts mirror the graph exactly (4 → 2 → 1).
      expect(
        summary.rounds.map((r) => r.fieldCount),
        graph.rounds.map((r) => r.fields.length),
      );
      expect(summary.rounds.map((r) => r.fieldCount), [4, 2, 1]);
    });

    test('surfaces per-round match format and ko tiebreak for each round', () {
      final graph = _koGraph();
      final summary = summarizeStageTypeGraph(graph);

      for (var i = 0; i < graph.rounds.length; i++) {
        expect(summary.rounds[i].matchFormat, graph.rounds[i].matchFormat);
        expect(summary.rounds[i].koTiebreak, graph.rounds[i].koTiebreak);
        expect(summary.rounds[i].koMatchup, graph.rounds[i].koMatchup);
      }

      // The three rounds carry three distinct time limits and the final's
      // no-tiebreak flag — all reach the summary unchanged.
      expect(
        summary.rounds.map((r) => r.matchFormat.timeLimitSeconds),
        [600, 720, 900],
      );
      expect(summary.rounds[2].matchFormat.finalNoTiebreak, isTrue);
      expect(
        summary.rounds.map((r) => r.koTiebreak),
        [
          KoTiebreakMethod.classicKingtossRemoval,
          KoTiebreakMethod.mightyFinisherShootout,
          KoTiebreakMethod.classicKingtossRemoval,
        ],
      );
    });

    test('attaches every edge to its source field or round transition', () {
      final graph = _koGraph();
      final summary = summarizeStageTypeGraph(graph);

      List<FieldEdge> outgoingOf(String id) => summary.rounds
          .expand((r) => r.fields)
          .firstWhere((f) => f.field.id == id)
          .outgoing;

      expect(outgoingOf('R1F1'),
          [const WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1')]);
      // R2F1 owns both a winner and a loser edge, in declaration order.
      expect(outgoingOf('R2F1'), [
        const WinnerEdge(fromFieldId: 'R2F1', toFieldId: 'R3F1'),
        const LoserEdge(fromFieldId: 'R2F1', toFieldId: 'R3F1'),
      ]);
      expect(outgoingOf('R2F2'),
          [const OpenEdge(fromFieldId: 'R2F2', slot: OpenEdgeSlot.winner)]);
      expect(outgoingOf('R3F1'), isEmpty);

      // No edges are silently lost: KO edges live on fields, advance-all on
      // rounds — together they account for the whole edge list.
      final fieldEdgeCount = summary.rounds
          .expand((r) => r.fields)
          .expand((f) => f.outgoing)
          .length;
      final advanceCount =
          summary.rounds.where((r) => r.advance != null).length;
      expect(fieldEdgeCount + advanceCount, graph.edges.length);
    });

    test('threads progress per round and field from materialized matches', () {
      final graph = _koGraph();
      final summary = summarizeStageTypeGraph(
        graph,
        progressByField: const {
          (1, 1): FieldMatchProgress.done,
          (1, 2): FieldMatchProgress.done,
          (1, 3): FieldMatchProgress.filled,
          // (1, 4) omitted → defaults to awaiting.
          (2, 1): FieldMatchProgress.filled,
        },
      );

      final r1 = summary.rounds.firstWhere((r) => r.roundNumber == 1);
      expect(r1.countOf(FieldMatchProgress.done), 2);
      expect(r1.countOf(FieldMatchProgress.filled), 1);
      expect(r1.countOf(FieldMatchProgress.awaiting), 1);

      final r3 = summary.rounds.firstWhere((r) => r.roundNumber == 3);
      expect(r3.countOf(FieldMatchProgress.awaiting), 1);

      expect(summary.totalOf(FieldMatchProgress.done), 2);
      expect(summary.totalOf(FieldMatchProgress.filled), 2);
      expect(summary.totalOf(FieldMatchProgress.awaiting), 3);
      expect(
        summary.totalOf(FieldMatchProgress.done) +
            summary.totalOf(FieldMatchProgress.filled) +
            summary.totalOf(FieldMatchProgress.awaiting),
        summary.totalFields,
      );
    });

    test('covers a Vorrunde graph with advance-all and pairing rules', () {
      final graph = _vorrundeGraph();
      final summary = summarizeStageTypeGraph(graph);

      expect(summary.category, TypeStageCategory.vorrunde);
      expect(summary.totalFields, 6);
      expect(summary.rounds.map((r) => r.fieldCount), [3, 3]);

      // Pairing rule is surfaced per round; KO fields stay null.
      expect(
        summary.rounds.map((r) => r.pairingRule),
        [TypePairingRule.groupRoundRobin, TypePairingRule.schochMonrad],
      );
      expect(summary.rounds.every((r) => r.koTiebreak == null), isTrue);

      // The single advance-all transition hangs off round 1, not on a field.
      expect(summary.rounds[0].advance,
          const AdvanceAllEdge(fromRound: 1, toRound: 2));
      expect(summary.rounds[1].advance, isNull);
      expect(
        summary.rounds.expand((r) => r.fields).expand((f) => f.outgoing),
        isEmpty,
        reason: 'Vorrunde routes per round, never per field',
      );
    });
  });

  group('classic (non-type-graph) stage stays backward-compatible', () {
    test('a classic KO node carries no type graph and its readers are stable',
        () {
      final node = StageNode(
        id: 'ko',
        type: StageNodeType.singleElim,
        seeding: StageSeedingSource.fromElo,
        config: writeKoNodeConfig(
          matchup: KoMatchup.seedHighVsLow,
          tiebreakMethod: KoTiebreakMethod.classicKingtossRemoval,
        ),
      );

      // No type_graph key → the Ebene-2 summary is simply never built for it.
      expect(node.config.containsKey('type_graph'), isFalse);

      // The classic config readers the Ebene-1 summary depends on are
      // unchanged: matchup and tiebreak still round-trip out of the config.
      expect(koMatchupFromConfig(node.config), KoMatchup.seedHighVsLow);
      expect(
        koTiebreakMethodFromConfig(node.config),
        KoTiebreakMethod.classicKingtossRemoval,
      );
      expect(koRoundFormatsFromConfig(node.config), isEmpty);
    });

    test('a classic Schoch node round count is read as before', () {
      final node = StageNode(
        id: 'schoch',
        type: StageNodeType.schoch,
        seeding: StageSeedingSource.fromElo,
        config: writeSchochNodeConfig(rounds: 6),
      );

      expect(node.config.containsKey('type_graph'), isFalse);
      expect(schochRoundsFromConfig(node.config), 6);
    });
  });
}
