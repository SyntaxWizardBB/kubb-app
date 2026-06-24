import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/stage_type_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/presentation/stage_type_graph_wizard_host.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// W5-T06: the wizard "Stufen-Typ modellieren" host writes the authored type
/// graph into the owning stage's `config['type_graph']`. On save the host hands
/// back the updated [StageNode]; the serialized graph must round-trip through
/// [StageTypeGraph.fromJson] and other config keys must survive.
void main() {
  const matchFormat = StageTypeGraphBuilderController.defaultMatchFormat;

  StageTypeGraph koValid() => StageTypeGraph(
        category: TypeStageCategory.ko,
        rounds: <TypeRound>[
          TypeRound(
            roundNumber: 1,
            fields: const <TypeField>[
              TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
              TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
            ],
            matchFormat: matchFormat,
            koMatchup: KoMatchup.seedHighVsLow,
          ),
          TypeRound(
            roundNumber: 2,
            fields: const <TypeField>[
              TypeField(id: 'R2F1', roundNumber: 2, slot: 1),
            ],
            matchFormat: matchFormat,
            koMatchup: KoMatchup.seedHighVsLow,
          ),
        ],
        edges: const <FieldEdge>[
          WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'),
          WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'),
        ],
      );

  testWidgets('onSave writes config[type_graph] and it round-trips',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final graph = koValid();
    final stage = StageNode(
      id: 'ko',
      type: StageNodeType.singleElim,
      seeding: StageSeedingSource.asRouted,
      config: const <String, Object?>{'qualifierCount': 2},
    );

    StageNode? saved;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stageTypeGraphBuilderProvider
              .overrideWith(() => StageTypeGraphBuilderController(graph)),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StageTypeGraphWizardHost(
              stage: stage,
              onSaved: (node) => saved = node,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    // The pre-existing config key survives the merge.
    expect(saved!.config['qualifierCount'], 2);

    final raw = saved!.config[stageTypeGraphConfigKey];
    expect(raw, isNotNull);

    // Round-trip: the written type_graph reconstructs the authored graph.
    final normalized = jsonDecode(jsonEncode(raw)) as Map<String, Object?>;
    final restored = StageTypeGraph.fromJson(normalized);
    expect(restored, graph);
  });
}
