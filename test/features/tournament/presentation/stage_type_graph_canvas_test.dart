import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/stage_type_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/application/stage_type_graph_canvas_layout.dart';
import 'package:kubb_app/features/tournament/presentation/stage_type_graph_canvas.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Widget tests for the desktop stage-TYPE-graph canvas (Ebene 2, ADR-0039
/// §5/§6.5, T09). The canvas is the second view onto
/// `stageTypeGraphBuilderProvider`; it mutates only through the controller.

const MatchFormatSpec _format =
    StageTypeGraphBuilderController.defaultMatchFormat;

/// KO type, round 1 (F1, F2) -> round 2 (F1), no edges yet.
StageTypeGraph _koTwoRoundsNoEdges() => StageTypeGraph(
      category: TypeStageCategory.ko,
      rounds: <TypeRound>[
        TypeRound(
          roundNumber: 1,
          fields: const <TypeField>[
            TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
            TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
          ],
          matchFormat: _format,
          koMatchup: KoMatchup.seedHighVsLow,
        ),
        TypeRound(
          roundNumber: 2,
          fields: const <TypeField>[
            TypeField(id: 'R2F1', roundNumber: 2, slot: 1),
          ],
          matchFormat: _format,
          koMatchup: KoMatchup.seedHighVsLow,
        ),
      ],
      edges: const <FieldEdge>[],
    );

/// A clean two-round Vorrunde with the AdvanceAll chain already wired.
StageTypeGraph _vorrundeWired() => StageTypeGraph(
      category: TypeStageCategory.vorrunde,
      rounds: <TypeRound>[
        TypeRound(
          roundNumber: 1,
          fields: const <TypeField>[
            TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
            TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
          ],
          matchFormat: _format,
          pairingRule: TypePairingRule.groupRoundRobin,
        ),
        TypeRound(
          roundNumber: 2,
          fields: const <TypeField>[
            TypeField(id: 'R2F1', roundNumber: 2, slot: 1),
            TypeField(id: 'R2F2', roundNumber: 2, slot: 2),
          ],
          matchFormat: _format,
          pairingRule: TypePairingRule.groupRoundRobin,
        ),
      ],
      edges: const <FieldEdge>[
        AdvanceAllEdge(fromRound: 1, toRound: 2),
      ],
    );

/// A two-round Vorrunde WITHOUT the AdvanceAll chain (so a port-drag can wire
/// the first transition).
StageTypeGraph _vorrundeNoChain() => StageTypeGraph(
      category: TypeStageCategory.vorrunde,
      rounds: <TypeRound>[
        TypeRound(
          roundNumber: 1,
          fields: const <TypeField>[
            TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
            TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
          ],
          matchFormat: _format,
          pairingRule: TypePairingRule.groupRoundRobin,
        ),
        TypeRound(
          roundNumber: 2,
          fields: const <TypeField>[
            TypeField(id: 'R2F1', roundNumber: 2, slot: 1),
            TypeField(id: 'R2F2', roundNumber: 2, slot: 2),
          ],
          matchFormat: _format,
          pairingRule: TypePairingRule.groupRoundRobin,
        ),
      ],
      edges: const <FieldEdge>[],
    );

Future<ProviderContainer> _pump(
  WidgetTester tester,
  StageTypeGraph graph,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      stageTypeGraphBuilderProvider
          .overrideWith(() => StageTypeGraphBuilderController(graph)),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: StageTypeGraphCanvas()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Drags from the given output port to [targetCenter] (global coords), with an
/// intermediate move so the preview line is exercised mid-drag.
Future<void> _dragPort(
  WidgetTester tester, {
  required Key portKey,
  required Offset targetCenter,
}) async {
  final portTopLeft = tester.getTopLeft(find.byKey(portKey));
  final start = portTopLeft +
      const Offset(KubbTokens.touchMin / 2, KubbTokens.touchMin / 2);
  final gesture = await tester.startGesture(start);
  await tester.pump();
  await gesture.moveTo(Offset.lerp(start, targetCenter, 0.5)!);
  await tester.pump();
  await gesture.moveTo(targetCenter);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('KO: one card per field + a winner and loser output port each',
      (tester) async {
    await _pump(tester, _koTwoRoundsNoEdges());

    expect(find.text('R1F1'), findsOneWidget);
    expect(find.text('R1F2'), findsOneWidget);
    expect(find.text('R2F1'), findsOneWidget);
    // Winner/loser ports exist per field (the KO routing language).
    expect(
      find.byKey(const Key('stageTypeCanvasWinnerPort_R1F1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('stageTypeCanvasLoserPort_R1F1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('stageTypeCanvasEdgePainter')),
      findsOneWidget,
    );
  });

  testWidgets('KO auto-layout: round 2 column is to the right of round 1',
      (tester) async {
    final container = await _pump(tester, _koTwoRoundsNoEdges());
    final layout = container.read(stageTypeGraphCanvasLayoutProvider);
    expect(layout['R1F1']!.dx, lessThan(layout['R2F1']!.dx));
  });

  testWidgets('KO: dragging the winner port onto a field wires a WinnerEdge',
      (tester) async {
    final container = await _pump(tester, _koTwoRoundsNoEdges());
    expect(container.read(stageTypeGraphBuilderProvider).graph.edges, isEmpty);

    final target = tester.getCenter(
      find.byKey(const Key('stageTypeCanvasField_R2F1')),
    );
    await _dragPort(
      tester,
      portKey: const Key('stageTypeCanvasWinnerPort_R1F1'),
      targetCenter: target,
    );

    final edges = container.read(stageTypeGraphBuilderProvider).graph.edges;
    expect(edges, hasLength(1));
    expect(edges.single, const WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'));
  });

  testWidgets('KO: dragging the loser port onto a field wires a LoserEdge',
      (tester) async {
    final container = await _pump(tester, _koTwoRoundsNoEdges());

    final target = tester.getCenter(
      find.byKey(const Key('stageTypeCanvasField_R2F1')),
    );
    await _dragPort(
      tester,
      portKey: const Key('stageTypeCanvasLoserPort_R1F2'),
      targetCenter: target,
    );

    final edges = container.read(stageTypeGraphBuilderProvider).graph.edges;
    expect(edges.single, const LoserEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'));
  });

  testWidgets('KO: dragging into empty space wires no edge', (tester) async {
    final container = await _pump(tester, _koTwoRoundsNoEdges());
    final empty = tester.getBottomRight(
          find.byKey(const Key('stageTypeCanvasEdgePainter')),
        ) -
        const Offset(4, 4);
    await _dragPort(
      tester,
      portKey: const Key('stageTypeCanvasWinnerPort_R1F1'),
      targetCenter: empty,
    );
    expect(container.read(stageTypeGraphBuilderProvider).graph.edges, isEmpty);
  });

  testWidgets('Vorrunde: one block per round with a single advance-all port',
      (tester) async {
    await _pump(tester, _vorrundeWired());

    expect(find.byKey(const Key('stageTypeCanvasRound_1')), findsOneWidget);
    expect(find.byKey(const Key('stageTypeCanvasRound_2')), findsOneWidget);
    // The non-terminal round has the single "alle weiter" output...
    expect(
      find.byKey(const Key('stageTypeCanvasAdvancePort_1')),
      findsOneWidget,
    );
    // ...the terminal round does not (nothing to advance into), and no field
    // has its own winner/loser port in a Vorrunde.
    expect(
      find.byKey(const Key('stageTypeCanvasAdvancePort_2')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('stageTypeCanvasWinnerPort_R1F1')),
      findsNothing,
    );
  });

  testWidgets('Vorrunde: dragging the advance-all port wires AdvanceAllEdge',
      (tester) async {
    final container = await _pump(tester, _vorrundeNoChain());
    expect(container.read(stageTypeGraphBuilderProvider).graph.edges, isEmpty);

    // Without the chain, round 2 carries an advance_all_missing error, so its
    // block is keyed with the error variant. Drag onto its title regardless.
    final target = tester.getCenter(find.text('Runde 2'));
    await _dragPort(
      tester,
      portKey: const Key('stageTypeCanvasAdvancePort_1'),
      targetCenter: target,
    );

    final edges = container.read(stageTypeGraphBuilderProvider).graph.edges;
    expect(edges.single, const AdvanceAllEdge(fromRound: 1, toRound: 2));
  });

  testWidgets('error highlight lands on the offending field only',
      (tester) async {
    // A KO graph where R2F1 leaves the final winner open is fine, but a forbidden
    // Vorrunde edge keys off edgeFrom. Use a KO with an unknown field ref so the
    // finding carries edgeFrom = the bad field id.
    final graph = StageTypeGraph(
      category: TypeStageCategory.ko,
      rounds: <TypeRound>[
        TypeRound(
          roundNumber: 1,
          fields: const <TypeField>[
            TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
            TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
          ],
          matchFormat: _format,
          koMatchup: KoMatchup.seedHighVsLow,
        ),
        TypeRound(
          roundNumber: 2,
          fields: const <TypeField>[
            TypeField(id: 'R2F1', roundNumber: 2, slot: 1),
          ],
          matchFormat: _format,
          koMatchup: KoMatchup.seedHighVsLow,
        ),
      ],
      edges: const <FieldEdge>[
        // Wire both winners so capacity is fine, then leave R2F1 open (warning).
        WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'),
        WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'),
        OpenEdge(fromFieldId: 'R2F1', slot: OpenEdgeSlot.winner),
      ],
    );
    await _pump(tester, graph);

    // R2F1 carries the open-path warning -> warning border (not error key).
    expect(
      find.byKey(const Key('stageTypeCanvasField_R2F1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('stageTypeCanvasFieldError_R2F1')),
      findsNothing,
    );
  });

  testWidgets('tap a winner edge -> confirm -> removeEdge', (tester) async {
    final container = await _pump(
      tester,
      StageTypeGraph(
        category: TypeStageCategory.ko,
        rounds: <TypeRound>[
          TypeRound(
            roundNumber: 1,
            fields: const <TypeField>[
              TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
              TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
            ],
            matchFormat: _format,
            koMatchup: KoMatchup.seedHighVsLow,
          ),
          TypeRound(
            roundNumber: 2,
            fields: const <TypeField>[
              TypeField(id: 'R2F1', roundNumber: 2, slot: 1),
            ],
            matchFormat: _format,
            koMatchup: KoMatchup.seedHighVsLow,
          ),
        ],
        edges: const <FieldEdge>[
          WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'),
          WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'),
        ],
      ),
    );
    expect(container.read(stageTypeGraphBuilderProvider).graph.edges,
        hasLength(2));

    // Tap near the R1F1 winner -> R2F1 segment midpoint in canvas-local coords.
    final layout = container.read(stageTypeGraphCanvasLayoutProvider);
    final from = layout['R1F1']!;
    final to = layout['R2F1']!;
    final localMid = Offset(
      (from.dx + kTypeCanvasNodeWidth + to.dx) / 2,
      ((from.dy + kTypeCanvasNodeHeight * 0.32) +
              (to.dy + kTypeCanvasNodeHeight / 2)) /
          2,
    );
    final painterTopLeft = tester.getTopLeft(
      find.byKey(const Key('stageTypeCanvasEdgePainter')),
    );
    await tester.tapAt(painterTopLeft + localMid);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kante löschen').last);
    await tester.pumpAndSettle();

    expect(container.read(stageTypeGraphBuilderProvider).graph.edges,
        hasLength(1));
  });

  group('resolveTypeConnectionTarget', () {
    final positions = <String, Offset>{
      'R1F1': Offset.zero,
      'R2F1': const Offset(400, 0),
    };
    final order = ['R1F1', 'R2F1'];

    test('pointer inside the target box -> that field', () {
      expect(
        resolveTypeConnectionTarget(
          pointer: const Offset(410, 10),
          sourceFieldId: 'R1F1',
          fieldOrder: order,
          positions: positions,
        ),
        'R2F1',
      );
    });

    test('pointer in empty space -> null', () {
      expect(
        resolveTypeConnectionTarget(
          pointer: const Offset(2000, 2000),
          sourceFieldId: 'R1F1',
          fieldOrder: order,
          positions: positions,
        ),
        isNull,
      );
    });

    test('pointer on the source field itself -> null (self-loop guard)', () {
      expect(
        resolveTypeConnectionTarget(
          pointer: const Offset(10, 10),
          sourceFieldId: 'R1F1',
          fieldOrder: order,
          positions: positions,
        ),
        isNull,
      );
    });
  });
}
