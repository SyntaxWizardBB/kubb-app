import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_bottom_sheet.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/data/stage_graph_templates_repository.dart';
import 'package:kubb_app/features/tournament/presentation/stage_graph_builder_screen.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/info_icon_button.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

StageNode _pool(String id) => StageNode(
      id: id,
      type: StageNodeType.groupPhase,
      seeding: StageSeedingSource.asRouted,
      config: const <String, Object?>{'groupCount': 2, 'qualifierCount': 2},
    );

StageNode _singleElim(String id) => StageNode(
      id: id,
      type: StageNodeType.singleElim,
      seeding: StageSeedingSource.asRouted,
    );

Future<void> _pump(
  WidgetTester tester, {
  required StageGraph graph,
  int fieldSize = 8,
  List<StageGraphTemplate> templates = const <StageGraphTemplate>[],
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = StageGraphBuilderController(graph, fieldSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stageGraphBuilderProvider.overrideWith(() => controller),
        stageGraphTemplatesProvider.overrideWith((_) async => templates),
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
}

/// Taps the info-glyph whose tooltip matches [title] and asserts the explainer
/// dialog shows [bodyFragment], then closes it.
Future<void> _openAndExpect(
  WidgetTester tester, {
  required String title,
  required String bodyFragment,
}) async {
  final button = find.descendant(
    of: find.byType(InfoIconButton),
    matching: find.byTooltip(title),
  );
  expect(button, findsOneWidget, reason: 'missing info button "$title"');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();

  // The explainer is a KubbBottomSheet carrying [title]; scope the body
  // assertion to it. The underlying node/edge dialog stays in the tree behind
  // it and may repeat the same caption (the selector explainer reuses the field
  // hint), so a global textContaining would match twice.
  final sheet = find.widgetWithText(KubbBottomSheet, title);
  expect(sheet, findsOneWidget);
  expect(
    find.descendant(of: sheet, matching: find.textContaining(bodyFragment)),
    findsOneWidget,
  );

  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('template bar carries an info button', (tester) async {
    await _pump(
      tester,
      graph: StageGraph(nodes: <StageNode>[_pool('groups')], edges: const []),
    );

    await _openAndExpect(
      tester,
      title: 'Vorlage wählen',
      bodyFragment: 'gespeicherte Vorlage',
    );
  });

  testWidgets('node dialog carries name and seeding-source info buttons',
      (tester) async {
    await _pump(
      tester,
      graph: StageGraph(nodes: <StageNode>[_pool('groups')], edges: const []),
    );

    await tester.tap(find.byTooltip('Stufe hinzufügen').first);
    await tester.pumpAndSettle();

    await _openAndExpect(
      tester,
      title: 'Name der Stufe',
      bodyFragment: 'Frei wählbarer Name',
    );
    await _openAndExpect(
      tester,
      title: 'Woher die Startreihenfolge kommt',
      bodyFragment: 'Setzliste für diese Stufe',
    );
    // The existing stage-type button still works.
    await _openAndExpect(
      tester,
      title: 'Stufentyp',
      bodyFragment: 'in seiner Gruppe',
    );
  });

  testWidgets('pool node config carries group-count and qualifier info buttons',
      (tester) async {
    await _pump(
      tester,
      graph: StageGraph(nodes: <StageNode>[_pool('groups')], edges: const []),
    );

    await tester.tap(find.byTooltip('Stufe hinzufügen').first);
    await tester.pumpAndSettle();

    await _openAndExpect(
      tester,
      title: 'Anzahl Gruppen',
      bodyFragment: 'aufgeteilt wird',
    );
    await _openAndExpect(
      tester,
      title: 'Wie viele pro Gruppe weiterkommen',
      bodyFragment: 'über alle Gruppen zusammen',
    );
  });

  testWidgets('KO node config carries matchup, tiebreak, reset and round info',
      (tester) async {
    await _pump(
      tester,
      graph: StageGraph(
        nodes: <StageNode>[_singleElim('cup')],
        edges: const [],
      ),
    );

    // Edit the existing KO node so its KO config fields render.
    await tester.tap(find.byTooltip('Stufe bearbeiten').first);
    await tester.pumpAndSettle();

    await _openAndExpect(
      tester,
      title: 'Wer gegen wen',
      bodyFragment: 'Paarungen im K.-o.',
    );
    await _openAndExpect(
      tester,
      title: 'Entscheid bei Gleichstand',
      bodyFragment: 'Mighty-Finisher',
    );
    await _openAndExpect(
      tester,
      title: 'Wie viele Runden',
      bodyFragment: 'K.-o.-Baum dieser Stufe',
    );
    await _openAndExpect(
      tester,
      title: 'Regeln je Runde',
      bodyFragment: 'wie viele Sätze zum Sieg',
    );
  });

  testWidgets('edge dialog carries from/to and selector info buttons',
      (tester) async {
    await _pump(
      tester,
      graph: StageGraph(
        nodes: <StageNode>[_pool('groups'), _singleElim('cup')],
        edges: const [],
      ),
    );

    await tester.tap(find.byTooltip('Kante hinzufügen').first);
    await tester.pumpAndSettle();

    await _openAndExpect(
      tester,
      title: 'Verbindung zwischen Stufen',
      bodyFragment: 'leitet Teilnehmer',
    );
    // Selector button reuses the chosen kind's explainer (default TopK).
    await _openAndExpect(
      tester,
      title: 'Selektor — wer weiterkommt',
      bodyFragment: 'besten K jeder Quell-Stufe',
    );
  });
}
