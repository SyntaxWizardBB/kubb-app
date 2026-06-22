import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/stage_type_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/data/stage_graph_templates_repository.dart'
    show TemplateVisibility;
import 'package:kubb_app/features/tournament/data/stage_type_templates_repository.dart';
import 'package:kubb_app/features/tournament/presentation/stage_type_graph_builder_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Setup-selection tests for the Ebene-2 stage-type template bar (T12, spec
/// §6/§9.6). Asserts the two contract behaviours the brief calls out:
///   * apply -> the controller loads the template's type graph (loadFromGraph)
///   * save -> the bar persists the current builder graph through the repo
///     (save), and the list refreshes to show it.

const MatchFormatSpec _matchFormat =
    StageTypeGraphBuilderController.defaultMatchFormat;

/// A fresh KO graph (the editor's default round 1) for the builder start state.
StageTypeGraph _freshKo() => StageTypeGraph(
      category: TypeStageCategory.ko,
      rounds: <TypeRound>[
        TypeRound(
          roundNumber: 1,
          fields: const <TypeField>[
            TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
          ],
          matchFormat: _matchFormat,
          koMatchup: KoMatchup.seedHighVsLow,
        ),
      ],
      edges: const <FieldEdge>[],
    );

/// A distinct Vorrunde graph the applied template carries — so loading it is
/// observable (the builder switches category).
StageTypeGraph _templateVorrunde() => StageTypeGraph(
      category: TypeStageCategory.vorrunde,
      rounds: <TypeRound>[
        TypeRound(
          roundNumber: 1,
          fields: const <TypeField>[
            TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
            TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
          ],
          matchFormat: _matchFormat,
          pairingRule: TypePairingRule.groupRoundRobin,
        ),
      ],
      edges: const <FieldEdge>[],
    );

StageTypeTemplate _template(StageTypeGraph graph) => StageTypeTemplate(
      id: 'tpl-1',
      name: 'Mein Typ',
      description: null,
      visibility: TemplateVisibility.public,
      category: graph.category,
      typeGraph: graph,
      isSystem: true,
    );

/// Capturing fake repo: serves the list via the seam, records save calls.
class _FakeRepo extends StageTypeTemplatesRepository {
  _FakeRepo()
      : super.withSeams(
          select: (_) async => const <dynamic>[],
          rpc: (_, _) async => null,
        );

  final List<({String name, TemplateVisibility visibility, StageTypeGraph graph})>
      saved = [];

  @override
  Future<String> saveTemplate({
    required String name,
    required TemplateVisibility visibility,
    required StageTypeGraph typeGraph,
    String? description,
    String? organizerTeamId,
    String? templateId,
  }) async {
    saved.add((name: name, visibility: visibility, graph: typeGraph));
    return 'saved-id';
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required StageTypeGraph builderStart,
  required List<StageTypeTemplate> templates,
  required StageTypeTemplatesRepository repo,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(390, 1400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      stageTypeGraphBuilderProvider
          .overrideWith(() => StageTypeGraphBuilderController(builderStart)),
      stageTypeTemplatesRepositoryProvider.overrideWithValue(repo),
      stageTypeTemplatesProvider.overrideWith((ref) async => templates),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const StageTypeGraphBuilderScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('apply: the controller loads the picked template graph',
      (tester) async {
    final container = await _pump(
      tester,
      builderStart: _freshKo(),
      templates: [_template(_templateVorrunde())],
      repo: _FakeRepo(),
    );

    // Pick the template in the dropdown.
    await tester.ensureVisible(find.byKey(const Key('stageTypeTemplatePicker')));
    await tester.tap(find.byKey(const Key('stageTypeTemplatePicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mein Typ').last);
    await tester.pumpAndSettle();

    // Apply.
    await tester.ensureVisible(find.byKey(const Key('stageTypeTemplateApply')));
    await tester.tap(find.byKey(const Key('stageTypeTemplateApply')));
    await tester.pumpAndSettle();

    // The shared builder now holds the template's (Vorrunde) graph.
    final loaded = container.read(stageTypeGraphBuilderProvider).graph;
    expect(loaded.category, TypeStageCategory.vorrunde);
    expect(loaded, _templateVorrunde());
  });

  testWidgets('save: persists the current builder graph through the repo',
      (tester) async {
    final repo = _FakeRepo();
    await _pump(
      tester,
      builderStart: _freshKo(),
      templates: const <StageTypeTemplate>[],
      repo: repo,
    );

    await tester.ensureVisible(find.byKey(const Key('stageTypeTemplateSave')));
    await tester.tap(find.byKey(const Key('stageTypeTemplateSave')));
    await tester.pumpAndSettle();

    // The shared SaveTemplateDialog appears: name it and confirm.
    await tester.enterText(
      find.byKey(const Key('stageGraphTemplateNameField')),
      'KO 8',
    );
    await tester.tap(find.text('Bestätigen'));
    await tester.pumpAndSettle();

    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.name, 'KO 8');
    // The saved graph is the current builder graph.
    expect(repo.saved.single.graph, _freshKo());
    // Standalone editor has no organizing team -> never club-scoped.
    expect(repo.saved.single.visibility, isNot(TemplateVisibility.club));
  });
}
