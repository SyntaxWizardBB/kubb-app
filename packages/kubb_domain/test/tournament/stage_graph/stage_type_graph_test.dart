import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _format = MatchFormatSpec(
  setsToWin: 2,
  maxSets: 3,
  timeLimitSeconds: 600,
);

void main() {
  group('FieldEdge JSON round-trip', () {
    test('WinnerEdge survives toJson/fromJson', () {
      const edge = WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1');
      final back = FieldEdge.fromJson(edge.toJson());
      expect(back, edge);
      expect(edge.toJson()['kind'], 'winner');
    });

    test('LoserEdge survives toJson/fromJson', () {
      const edge = LoserEdge(fromFieldId: 'R1F2', toFieldId: 'C1F1');
      final back = FieldEdge.fromJson(edge.toJson());
      expect(back, edge);
      expect(edge.toJson()['kind'], 'loser');
    });

    test('OpenEdge survives toJson/fromJson for both slots', () {
      const winnerOpen = OpenEdge(fromFieldId: 'R1F1', slot: OpenEdgeSlot.winner);
      const loserOpen = OpenEdge(fromFieldId: 'R1F1', slot: OpenEdgeSlot.loser);
      expect(FieldEdge.fromJson(winnerOpen.toJson()), winnerOpen);
      expect(FieldEdge.fromJson(loserOpen.toJson()), loserOpen);
      expect(winnerOpen.toJson()['slot'], 'winner');
    });

    test('AdvanceAllEdge survives toJson/fromJson', () {
      const edge = AdvanceAllEdge(fromRound: 1, toRound: 2);
      final back = FieldEdge.fromJson(edge.toJson());
      expect(back, edge);
      expect(edge.toJson()['kind'], 'advance_all');
    });

    test('fromJson throws on an unknown kind', () {
      expect(
        () => FieldEdge.fromJson(<String, Object?>{'kind': 'bogus'}),
        throwsArgumentError,
      );
    });
  });

  group('StageTypeGraph JSON round-trip', () {
    test('a KO graph with winner + loser + open edges round-trips', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.ko,
        rounds: [
          TypeRound(
            roundNumber: 1,
            fields: const [
              TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
              TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
            ],
            matchFormat: _format,
            koMatchup: KoMatchup.seedHighVsLow,
            koTiebreak: KoTiebreakMethod.classicKingtossRemoval,
          ),
          TypeRound(
            roundNumber: 2,
            fields: const [TypeField(id: 'R2F1', roundNumber: 2, slot: 1)],
            matchFormat: _format,
          ),
        ],
        edges: const [
          WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'),
          WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'),
          LoserEdge(fromFieldId: 'R1F1', toFieldId: 'R1F2'),
          OpenEdge(fromFieldId: 'R2F1', slot: OpenEdgeSlot.loser),
        ],
      );
      final back = StageTypeGraph.fromJson(graph.toJson());
      expect(back, graph);
      expect(back.rounds.first.koMatchup, KoMatchup.seedHighVsLow);
      expect(back.allFields.length, 3);
    });

    test('a Vorrunde graph with AdvanceAllEdge + pairingRule round-trips', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.vorrunde,
        rounds: [
          TypeRound(
            roundNumber: 1,
            fields: const [
              TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
              TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
            ],
            matchFormat: _format,
            pairingRule: TypePairingRule.schochMonrad,
          ),
          TypeRound(
            roundNumber: 2,
            fields: const [
              TypeField(id: 'R2F1', roundNumber: 2, slot: 1),
              TypeField(id: 'R2F2', roundNumber: 2, slot: 2),
            ],
            matchFormat: _format,
          ),
        ],
        edges: const [AdvanceAllEdge(fromRound: 1, toRound: 2)],
      );
      final back = StageTypeGraph.fromJson(graph.toJson());
      expect(back, graph);
      expect(back.category, TypeStageCategory.vorrunde);
      expect(back.rounds.first.pairingRule, TypePairingRule.schochMonrad);
    });

    test('fromJson tolerates absent optional round config (null)', () {
      final json = <String, Object?>{
        'category': 'vorrunde',
        'rounds': <Object?>[
          <String, Object?>{
            'round_number': 1,
            'fields': <Object?>[
              <String, Object?>{'id': 'R1F1', 'round_number': 1, 'slot': 1},
            ],
            'match_format': _format.toJson(),
          },
        ],
        'edges': <Object?>[],
      };
      final graph = StageTypeGraph.fromJson(json);
      expect(graph.rounds.first.koMatchup, isNull);
      expect(graph.rounds.first.pairingRule, isNull);
    });

    Glados<int>(any.intInRange(1, 9)).test(
      'KO round-1 graph round-trips for any participant count',
      (count) {
        final fields = generateRound1(TypeStageCategory.ko, count);
        final graph = StageTypeGraph(
          category: TypeStageCategory.ko,
          rounds: [
            TypeRound(roundNumber: 1, fields: fields, matchFormat: _format),
          ],
          edges: const [],
        );
        expect(StageTypeGraph.fromJson(graph.toJson()), graph);
      },
    );
  });

  group('generateRound1', () {
    test('KO with 16 participants yields F1..F8', () {
      final fields = generateRound1(TypeStageCategory.ko, 16);
      expect(fields.map((f) => f.id), [
        'R1F1',
        'R1F2',
        'R1F3',
        'R1F4',
        'R1F5',
        'R1F6',
        'R1F7',
        'R1F8',
      ]);
      expect(fields.every((f) => f.roundNumber == 1), isTrue);
    });

    test('Vorrunde with 8 participants yields 4 constant plates', () {
      final fields = generateRound1(TypeStageCategory.vorrunde, 8);
      expect(fields.length, 4);
      expect(fields.last.slot, 4);
    });

    test('an odd count yields one bye field (ceil n/2)', () {
      final ko = generateRound1(TypeStageCategory.ko, 9);
      expect(ko.length, 5);
      final vor = generateRound1(TypeStageCategory.vorrunde, 7);
      expect(vor.length, 4);
    });

    test('a single participant yields one (bye) field', () {
      expect(generateRound1(TypeStageCategory.ko, 1).length, 1);
    });

    test('a count below one is rejected', () {
      expect(
        () => generateRound1(TypeStageCategory.ko, 0),
        throwsArgumentError,
      );
    });

    Glados<int>(any.intInRange(1, 64)).test(
      'field count is always ceil(n / 2) and slots are 1-based contiguous',
      (count) {
        final fields = generateRound1(TypeStageCategory.vorrunde, count);
        expect(fields.length, (count + 1) ~/ 2);
        for (var i = 0; i < fields.length; i++) {
          expect(fields[i].slot, i + 1);
          expect(fields[i].roundNumber, 1);
        }
      },
    );
  });

  group('enum wire round-trips', () {
    test('TypeStageCategory', () {
      for (final v in TypeStageCategory.values) {
        expect(TypeStageCategory.fromWire(v.toWire()), v);
      }
      expect(
        () => TypeStageCategory.fromWire('nope'),
        throwsArgumentError,
      );
    });

    test('TypePairingRule', () {
      for (final v in TypePairingRule.values) {
        expect(TypePairingRule.fromWire(v.toWire()), v);
      }
    });

    test('OpenEdgeSlot', () {
      for (final v in OpenEdgeSlot.values) {
        expect(OpenEdgeSlot.fromWire(v.toWire()), v);
      }
    });
  });
}
