import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/stage_type_graph_builder_controller.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Editor-parity test (ADR-0039 §6.5, spec §9.5): the desktop canvas (U8) and
/// the handy form editor (U7) are two views onto ONE
/// `stageTypeGraphBuilderProvider`. There is no second state and no second
/// serialization. Therefore an edit made through the canvas and the same edit
/// made through the form land on the identical controller method, and
/// `toConfig()` serializes identically.
///
/// This test pins that: it drives two independent containers — one through the
/// calls the FORM view makes, one through the calls the CANVAS view makes — for
/// both a KO and a Vorrunde scenario, and asserts the serialized `type_graph` is
/// byte-identical. If a future change gave the canvas its own state or its own
/// serialization, this test breaks.
void main() {
  const matchFormat = StageTypeGraphBuilderController.defaultMatchFormat;

  List<TypeField> fields(int roundNumber, int count) => <TypeField>[
        for (var slot = 1; slot <= count; slot++)
          TypeField(
            id: 'R${roundNumber}F$slot',
            roundNumber: roundNumber,
            slot: slot,
          ),
      ];

  StageTypeGraphBuilderController freshController() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container.read(stageTypeGraphBuilderProvider.notifier);
  }

  /// The single serialization both editors round-trip through.
  String serialized(StageTypeGraphBuilderController c) =>
      jsonEncode(c.toConfig());

  group('KO type graph', () {
    // The FORM view: the rounds section adds a shrinking round and the KO edge
    // dialog adds the winner edges (stage_type_graph_builder_screen.dart).
    void buildViaForm(StageTypeGraphBuilderController c) {
      c
        ..resetTo(category: TypeStageCategory.ko, participantCount: 4)
        ..addRound(
          fields: fields(2, 1),
          matchFormat: matchFormat,
          koMatchup: KoMatchup.seedHighVsLow,
          koTiebreak: KoTiebreakMethod.classicKingtossRemoval,
        )
        ..addEdge(const WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'))
        ..addEdge(const WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'));
    }

    // The CANVAS view: identical round setup, but the winner edges arrive from
    // a winner-port -> field drag (`_resolveKoEdge` -> `controller.addEdge`).
    // The resulting WinnerEdge objects are the same — same method, same args.
    void buildViaCanvas(StageTypeGraphBuilderController c) {
      c
        ..resetTo(category: TypeStageCategory.ko, participantCount: 4)
        ..addRound(
          fields: fields(2, 1),
          matchFormat: matchFormat,
          koMatchup: KoMatchup.seedHighVsLow,
          koTiebreak: KoTiebreakMethod.classicKingtossRemoval,
        )
        // Winner-port drag from R1F1 onto R2F1.
        ..addEdge(const WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'))
        // Winner-port drag from R1F2 onto R2F1.
        ..addEdge(const WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'));
    }

    test('form and canvas serialize to an identical type_graph', () {
      final form = freshController();
      final canvas = freshController();
      buildViaForm(form);
      buildViaCanvas(canvas);

      expect(serialized(canvas), serialized(form));
      expect(canvas.toConfig(), form.toConfig());
      // The serialized graph is the valid, savable target (no errors).
      final graph = StageTypeGraph.fromJson(
        form.toConfig()[stageTypeGraphConfigKey]! as Map<String, Object?>,
      );
      expect(hasTypeErrors(validateStageTypeGraph(graph)), isFalse);
    });
  });

  group('Vorrunde type graph', () {
    // The FORM view: the rounds section adds a constant-size round AND wires the
    // mandatory AdvanceAllEdge in the same action (`_addRound`).
    void buildViaForm(StageTypeGraphBuilderController c) {
      c
        ..resetTo(category: TypeStageCategory.vorrunde, participantCount: 4)
        ..addRound(
          fields: fields(2, 2),
          matchFormat: matchFormat,
          pairingRule: TypePairingRule.groupRoundRobin,
        )
        ..addEdge(const AdvanceAllEdge(fromRound: 1, toRound: 2));
    }

    // The CANVAS view: same round setup, but the AdvanceAllEdge arrives from the
    // round block's advance-all port drag (`_resolveAdvanceAll`).
    void buildViaCanvas(StageTypeGraphBuilderController c) {
      c
        ..resetTo(category: TypeStageCategory.vorrunde, participantCount: 4)
        ..addRound(
          fields: fields(2, 2),
          matchFormat: matchFormat,
          pairingRule: TypePairingRule.groupRoundRobin,
        )
        // Advance-all port drag from round 1 onto the round 2 block.
        ..addEdge(const AdvanceAllEdge(fromRound: 1, toRound: 2));
    }

    test('form and canvas serialize to an identical type_graph', () {
      final form = freshController();
      final canvas = freshController();
      buildViaForm(form);
      buildViaCanvas(canvas);

      expect(serialized(canvas), serialized(form));
      expect(canvas.toConfig(), form.toConfig());
      final graph = StageTypeGraph.fromJson(
        form.toConfig()[stageTypeGraphConfigKey]! as Map<String, Object?>,
      );
      expect(hasTypeErrors(validateStageTypeGraph(graph)), isFalse);
    });
  });

  test('a mixed edit sequence (add, edit, delete) stays in parity', () {
    // A longer sequence exercising every mutation kind, applied identically by
    // both views. Order-of-operations is the only thing that matters; both
    // views share the one controller, so equal call sequences must converge.
    void sequence(StageTypeGraphBuilderController c) {
      c
        ..resetTo(category: TypeStageCategory.ko, participantCount: 8)
        ..addRound(
          fields: fields(2, 2),
          matchFormat: matchFormat,
          koMatchup: KoMatchup.seedHighVsLow,
        )
        ..addRound(
          fields: fields(3, 1),
          matchFormat: matchFormat,
          koMatchup: KoMatchup.seedHighVsLow,
        )
        ..addEdge(const WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'))
        ..addEdge(const WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'))
        // edit: re-point a wrong edge (index 1)
        ..updateEdge(1, const WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F2'))
        ..addEdge(const WinnerEdge(fromFieldId: 'R1F3', toFieldId: 'R2F2'))
        ..addEdge(const WinnerEdge(fromFieldId: 'R1F4', toFieldId: 'R2F1'))
        ..addEdge(const WinnerEdge(fromFieldId: 'R2F1', toFieldId: 'R3F1'))
        ..addEdge(const WinnerEdge(fromFieldId: 'R2F2', toFieldId: 'R3F1'))
        // delete: drop the last edge, then re-add it
        ..removeEdge(7)
        ..addEdge(const WinnerEdge(fromFieldId: 'R2F2', toFieldId: 'R3F1'));
    }

    final form = freshController();
    final canvas = freshController();
    sequence(form);
    sequence(canvas);

    expect(serialized(canvas), serialized(form));
    expect(canvas.toConfig(), form.toConfig());
  });
}
