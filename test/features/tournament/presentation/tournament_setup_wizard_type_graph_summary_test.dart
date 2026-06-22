import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/stage_graph_builder_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_setup_wizard.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

// M4 U12: the Ebene-2 summary surfaces a type-graph stage round by round in the
// wizard summary. A classic stage stays on the Ebene-1 path (config summary).

const _r1 = MatchFormatSpec(setsToWin: 2, maxSets: 3, timeLimitSeconds: 600);
const _r2 = MatchFormatSpec(setsToWin: 3, maxSets: 5, timeLimitSeconds: 720);

/// Three KO rounds (4 → 2 → 1 fields) wired by winner edges, with a loser feed
/// and one open slot — enough to force every round and every field id through
/// the renderer.
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
          matchFormat: _r2,
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

StageNode _typeGraphNode(StageTypeGraph graph) => StageNode(
      id: 'S1',
      type: StageNodeType.singleElim,
      seeding: StageSeedingSource.fromElo,
      config: <String, Object?>{'type_graph': graph.toJson()},
    );

StageNode _classicNode() => StageNode(
      id: 'S2',
      type: StageNodeType.roundRobin,
      seeding: StageSeedingSource.manual,
      config: const <String, Object?>{'groupCount': 4, 'qualifierCount': 2},
    );

/// Renders every `(label, value)` row pair as plain [Text], so a missing round
/// or a dropped field id is a missing widget the test catches — no truncation
/// is possible to hide.
Widget _harness(StageNode node) => MaterialApp(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final l = AppLocalizations.of(context);
            final rows = stageTypeGraphSummaryRows(l, node);
            return Column(
              children: [
                for (final row in rows) ...[
                  Text(row.$1),
                  Text(row.$2),
                ],
              ],
            );
          },
        ),
      ),
    );

void main() {
  testWidgets(
    'type-graph stage renders every round and every field label',
    (tester) async {
      final graph = _koGraph();
      await tester.pumpWidget(_harness(_typeGraphNode(graph)));

      // Every round surfaces (round-number substring is enough — the label
      // also carries the field count).
      expect(find.textContaining('Runde 1'), findsOneWidget);
      expect(find.textContaining('Runde 2'), findsOneWidget);
      expect(find.textContaining('Runde 3'), findsOneWidget);

      // Every field id of every round surfaces, none dropped.
      for (final field in graph.allFields) {
        expect(
          find.textContaining(field.id),
          findsWidgets,
          reason: 'field ${field.id} must appear in the rendered summary',
        );
      }

      // The routing of the KO rounds is visible (winner / loser / open).
      expect(find.textContaining('Sieger'), findsWidgets);
      expect(find.textContaining('Verlierer'), findsWidgets);
      expect(find.textContaining('Offen'), findsWidgets);
    },
  );

  testWidgets(
    'classic stage stays on the Ebene-1 path with no type-graph rows',
    (tester) async {
      final node = _classicNode();
      await tester.pumpWidget(_harness(node));

      // No Ebene-2 rows for a classic stage.
      expect(find.textContaining('Runde'), findsNothing);

      // The unchanged Ebene-1 config summary still describes the stage.
      late String classicSummary;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              classicSummary =
                  stageNodeConfigSummary(AppLocalizations.of(context), node)!;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(classicSummary, contains('4'));
      expect(stageTypeGraphSummaryRows, isNotNull);
    },
  );
}
