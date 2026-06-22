import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('StageSeedingSource.random', () {
    test("fromWire('random') resolves to random", () {
      expect(StageSeedingSource.fromWire('random'), StageSeedingSource.random);
    });

    test("random.toWire() is 'random'", () {
      expect(StageSeedingSource.random.toWire(), 'random');
    });

    test('random survives a wire round-trip', () {
      expect(
        StageSeedingSource.fromWire(StageSeedingSource.random.toWire()),
        StageSeedingSource.random,
      );
    });

    test('node carrying random seeding round-trips through JSON', () {
      final node = StageNode(
        id: 's1',
        type: StageNodeType.groupPhase,
        seeding: StageSeedingSource.random,
      );
      final back = StageNode.fromJson(node.toJson());
      expect(back.seeding, StageSeedingSource.random);
      expect(node.toJson()['seeding'], 'random');
    });
  });
}
