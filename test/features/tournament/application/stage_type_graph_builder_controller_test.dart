import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/stage_type_graph_builder_controller.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Tests for the live-validating stage-type-graph editor controller (Ebene 2,
/// ADR-0039 §1 / §6.5).
void main() {
  const matchFormat = StageTypeGraphBuilderController.defaultMatchFormat;

  List<TypeField> fields(int roundNumber, int count) => <TypeField>[
        for (var slot = 1; slot <= count; slot++)
          TypeField(id: 'R${roundNumber}F$slot', roundNumber: roundNumber, slot: slot),
      ];

  late ProviderContainer container;
  late StageTypeGraphBuilderController controller;

  StageTypeGraphBuilderState read() =>
      container.read(stageTypeGraphBuilderProvider);

  setUp(() {
    container = ProviderContainer();
    controller = container.read(stageTypeGraphBuilderProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('build(): fresh KO round 1 with 16 participants -> F1..F8', () {
    final state = read();
    expect(state.graph.category, TypeStageCategory.ko);
    expect(state.graph.rounds, hasLength(1));
    expect(state.graph.rounds.single.fields, hasLength(8));
    expect(
      state.findings,
      validateStageTypeGraph(state.graph),
    );
    // A single round of 8 fields is the final-not-single error -> blocks.
    expect(state.hasErrors, isTrue);
  });

  test('resetTo(vorrunde): constant plates, no granular edges seeded', () {
    controller.resetTo(
      category: TypeStageCategory.vorrunde,
      participantCount: 8,
    );
    final state = read();
    expect(state.graph.category, TypeStageCategory.vorrunde);
    expect(state.graph.rounds.single.fields, hasLength(4));
    expect(state.graph.rounds.single.pairingRule, isNotNull);
    expect(state.graph.edges, isEmpty);
  });

  test('addRound + winner edges: a shrinking KO type validates clean', () {
    // Round 1 F1..F2 -> round 2 F1 (final), 4 participants.
    controller
      ..resetTo(category: TypeStageCategory.ko, participantCount: 4)
      ..addRound(
        fields: fields(2, 1),
        matchFormat: matchFormat,
        koMatchup: KoMatchup.seedHighVsLow,
      )
      ..addEdge(const WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'))
      ..addEdge(const WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'));

    final state = read();
    expect(state.graph.rounds, hasLength(2));
    expect(state.findings, validateStageTypeGraph(state.graph));
    expect(state.hasErrors, isFalse);
  });

  test('a granular winner edge in a Vorrunde -> vorrunde_field_edge_forbidden',
      () {
    // F1..F2 in round 1; add a second round with the AdvanceAll edge, then a
    // forbidden granular edge.
    controller
      ..resetTo(category: TypeStageCategory.vorrunde, participantCount: 4)
      ..addRound(
        fields: fields(2, 2),
        matchFormat: matchFormat,
        pairingRule: TypePairingRule.groupRoundRobin,
      )
      ..addEdge(const AdvanceAllEdge(fromRound: 1, toRound: 2))
      ..addEdge(const WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'));

    final state = read();
    expect(
      state.findings.any(
        (f) => f.code == TypeValidationCode.vorrundeFieldEdgeForbidden,
      ),
      isTrue,
    );
    // hasTypeErrors blocks save.
    expect(state.hasErrors, isTrue);
  });

  test('an open edge surfaces as a warning, not an error (save still allowed)',
      () {
    controller
      ..resetTo(category: TypeStageCategory.ko, participantCount: 4)
      ..addRound(
        fields: fields(2, 1),
        matchFormat: matchFormat,
        koMatchup: KoMatchup.seedHighVsLow,
      )
      // Wire both winners into the final; leave the final's winner open.
      ..addEdge(const WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'))
      ..addEdge(const WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'))
      ..addEdge(const OpenEdge(fromFieldId: 'R2F1', slot: OpenEdgeSlot.winner));

    final state = read();
    expect(
      state.findings.any((f) => f.code == TypeValidationCode.openPath),
      isTrue,
    );
    // Open is a warning -> does not block.
    expect(state.hasErrors, isFalse);
  });

  test('a KO round 2 with >= fields than round 1 -> ko_not_shrinking error', () {
    controller
      ..resetTo(category: TypeStageCategory.ko, participantCount: 4)
      ..addRound(
        fields: fields(2, 2), // same count as round 1 -> must shrink
        matchFormat: matchFormat,
        koMatchup: KoMatchup.seedHighVsLow,
      );
    final state = read();
    expect(
      state.findings.any((f) => f.code == TypeValidationCode.koNotShrinking),
      isTrue,
    );
    expect(state.hasErrors, isTrue);
  });

  test('removeRound strips edges that touch the removed round', () {
    controller
      ..resetTo(category: TypeStageCategory.ko, participantCount: 4)
      ..addRound(
        fields: fields(2, 1),
        matchFormat: matchFormat,
        koMatchup: KoMatchup.seedHighVsLow,
      )
      ..addEdge(const WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'))
      ..addEdge(const WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'))
      ..removeRound(2);

    final state = read();
    expect(state.graph.rounds, hasLength(1));
    // Both winner edges pointed at R2F1, so both are gone.
    expect(state.graph.edges, isEmpty);
  });

  test('updateEdge / removeEdge: out-of-range is a no-op', () {
    controller
      ..resetTo(category: TypeStageCategory.ko, participantCount: 4)
      ..addEdge(const WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R1F2'));
    final before = read().graph;

    controller
      ..updateEdge(9, const WinnerEdge(fromFieldId: 'x', toFieldId: 'y'))
      ..removeEdge(9);
    expect(read().graph, before);
  });

  test('toConfig: serializes under the single type_graph key, round-trips', () {
    controller
      ..resetTo(category: TypeStageCategory.ko, participantCount: 4)
      ..addRound(
        fields: fields(2, 1),
        matchFormat: matchFormat,
        koMatchup: KoMatchup.seedHighVsLow,
      )
      ..addEdge(const WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'))
      ..addEdge(const WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'));

    final config = controller.toConfig();
    expect(config.keys, <String>[stageTypeGraphConfigKey]);
    final roundTripped = StageTypeGraph.fromJson(
      config[stageTypeGraphConfigKey]! as Map<String, Object?>,
    );
    expect(roundTripped, read().graph);
  });

  test('determinism: identical mutation sequence => identical state', () {
    void mutate(StageTypeGraphBuilderController c) {
      c
        ..resetTo(category: TypeStageCategory.ko, participantCount: 4)
        ..addRound(
          fields: fields(2, 1),
          matchFormat: matchFormat,
          koMatchup: KoMatchup.seedHighVsLow,
        )
        ..addEdge(const WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'))
        ..addEdge(const WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'));
    }

    mutate(controller);
    final s1 = read();

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    mutate(container2.read(stageTypeGraphBuilderProvider.notifier));
    final s2 = container2.read(stageTypeGraphBuilderProvider);

    expect(s1.graph, s2.graph);
    expect(s1.findings, s2.findings);
    expect(s1, s2);
  });
}
