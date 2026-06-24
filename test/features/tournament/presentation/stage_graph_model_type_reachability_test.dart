import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/application/stage_type_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/data/stage_graph_templates_repository.dart';
import 'package:kubb_app/features/tournament/presentation/stage_graph_builder_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

// Proves the Ebene-2 type-graph editor is reachable from the Ebene-1 builder:
// the per-node "Stufen-Typ modellieren" affordance opens the editor for THAT
// node and writes the authored graph back into the node's config['type_graph']
// via the builder controller, keeping the node's other config keys.

const MatchFormatSpec _matchFormat =
    StageTypeGraphBuilderController.defaultMatchFormat;

StageTypeGraph _koValid() => StageTypeGraph(
      category: TypeStageCategory.ko,
      rounds: <TypeRound>[
        TypeRound(
          roundNumber: 1,
          fields: const <TypeField>[
            TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
            TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
          ],
          matchFormat: _matchFormat,
          koMatchup: KoMatchup.seedHighVsLow,
        ),
        TypeRound(
          roundNumber: 2,
          fields: const <TypeField>[
            TypeField(id: 'R2F1', roundNumber: 2, slot: 1),
          ],
          matchFormat: _matchFormat,
          koMatchup: KoMatchup.seedHighVsLow,
        ),
      ],
      edges: const <FieldEdge>[
        WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'),
        WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'),
      ],
    );

StageGraph _graphWith(StageNode node) =>
    StageGraph(nodes: <StageNode>[node], edges: const <StageEdge>[]);

void main() {
  testWidgets(
      'from the Ebene-1 builder, the type-graph editor opens and writes '
      'config[type_graph] back onto the node, keeping other config keys',
      (tester) async {
    // A roomy viewport so the form-only editor and its save bar fit.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The KO node opens the editor pre-seeded with a valid graph, so Save is
    // enabled (a fresh graph would still validate, but seeding makes the
    // round-trip assertion meaningful). It also carries a sibling config key
    // we expect to survive the write-back.
    final seed = _koValid();
    final node = StageNode(
      id: 'ko',
      type: StageNodeType.singleElim,
      seeding: StageSeedingSource.asRouted,
      config: <String, Object?>{
        'qualifierCount': 2,
        stageTypeGraphConfigKey: seed.toJson(),
      },
    );

    final controller = StageGraphBuilderController(_graphWith(node), 8);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stageGraphBuilderProvider.overrideWith(() => controller),
          stageGraphTemplatesProvider
              .overrideWith((_) async => const <StageGraphTemplate>[]),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const StageGraphBuilderScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The affordance is on the node tile in the Ebene-1 builder.
    final affordance = find.byKey(const Key('stageGraphModelType_ko'));
    expect(affordance, findsOneWidget);
    await tester.ensureVisible(affordance);
    await tester.tap(affordance);
    await tester.pumpAndSettle();

    // The editor opened (its save bar is on screen).
    expect(find.text('Speichern'), findsOneWidget);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    // Back on the builder: the controller's node now carries the authored
    // type graph, and its pre-existing key survived the write-back.
    final saved =
        controller.state.graph.nodes.firstWhere((n) => n.id == 'ko');
    expect(saved.config['qualifierCount'], 2);

    final raw = saved.config[stageTypeGraphConfigKey];
    expect(raw, isNotNull);

    // Round-trip: the written config reconstructs the authored graph.
    final normalized = jsonDecode(jsonEncode(raw)) as Map<String, Object?>;
    expect(StageTypeGraph.fromJson(normalized), seed);

    // The save confirmation surfaced.
    expect(find.text('Stufen-Typ gespeichert'), findsOneWidget);
  });

  testWidgets('a shoot-out qualification node offers no type-graph affordance',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final node = StageNode(
      id: 'shoot',
      type: StageNodeType.shootoutQuali,
      seeding: StageSeedingSource.asRouted,
      config: const <String, Object?>{'slots': 8},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stageGraphBuilderProvider
              .overrideWith(() => StageGraphBuilderController(_graphWith(node), 8)),
          stageGraphTemplatesProvider
              .overrideWith((_) async => const <StageGraphTemplate>[]),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const StageGraphBuilderScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stageGraphModelType_shoot')), findsNothing);
  });
}
