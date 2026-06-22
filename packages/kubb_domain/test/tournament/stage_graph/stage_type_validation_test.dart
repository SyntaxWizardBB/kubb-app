import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

const _format = MatchFormatSpec(
  setsToWin: 2,
  maxSets: 3,
  timeLimitSeconds: 600,
);

TypeField _field(int round, int slot) =>
    TypeField(id: 'R${round}F$slot', roundNumber: round, slot: slot);

List<TypeField> _fields(int round, int count) =>
    [for (var s = 1; s <= count; s++) _field(round, s)];

TypeRound _round(int number, int fieldCount, {TypePairingRule? pairing}) =>
    TypeRound(
      roundNumber: number,
      fields: _fields(number, fieldCount),
      matchFormat: _format,
      pairingRule: pairing,
    );

bool _hasCode(List<ValidationFinding> findings, String code) =>
    findings.any((f) => f.code == code);

void main() {
  group('KO validation', () {
    test('a shrinking 4-2-1 bracket with winner edges is error-free', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.ko,
        rounds: [_round(1, 4), _round(2, 2), _round(3, 1)],
        edges: const [
          WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'),
          WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'),
          WinnerEdge(fromFieldId: 'R1F3', toFieldId: 'R2F2'),
          WinnerEdge(fromFieldId: 'R1F4', toFieldId: 'R2F2'),
          WinnerEdge(fromFieldId: 'R2F1', toFieldId: 'R3F1'),
          WinnerEdge(fromFieldId: 'R2F2', toFieldId: 'R3F1'),
        ],
      );
      final findings = validateStageTypeGraph(graph);
      expect(hasTypeErrors(findings), isFalse, reason: findings.toString());
    });

    test('a non-shrinking round 2 is an error', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.ko,
        rounds: [_round(1, 2), _round(2, 2)],
        edges: const [],
      );
      final findings = validateStageTypeGraph(graph);
      expect(_hasCode(findings, TypeValidationCode.koNotShrinking), isTrue);
      expect(hasTypeErrors(findings), isTrue);
    });

    test('a final round with more than one field is an error', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.ko,
        rounds: [_round(1, 4), _round(2, 2)],
        edges: const [],
      );
      final findings = validateStageTypeGraph(graph);
      expect(_hasCode(findings, TypeValidationCode.koFinalNotSingle), isTrue);
    });

    test('a capacity mismatch (3 -> 1) is an error', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.ko,
        rounds: [_round(1, 3), _round(2, 1)],
        edges: const [],
      );
      final findings = validateStageTypeGraph(graph);
      expect(_hasCode(findings, TypeValidationCode.koCapacityMismatch), isTrue);
    });
  });

  group('Vorrunde validation', () {
    test('a constant 4-4-4 graph with AdvanceAllEdges is error-free', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.vorrunde,
        rounds: [
          _round(1, 4, pairing: TypePairingRule.schochMonrad),
          _round(2, 4, pairing: TypePairingRule.schochMonrad),
          _round(3, 4),
        ],
        edges: const [
          AdvanceAllEdge(fromRound: 1, toRound: 2),
          AdvanceAllEdge(fromRound: 2, toRound: 3),
        ],
      );
      final findings = validateStageTypeGraph(graph);
      expect(hasTypeErrors(findings), isFalse, reason: findings.toString());
    });

    test('a decreasing field count is an error', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.vorrunde,
        rounds: [_round(1, 4), _round(2, 2)],
        edges: const [AdvanceAllEdge(fromRound: 1, toRound: 2)],
      );
      final findings = validateStageTypeGraph(graph);
      expect(_hasCode(findings, TypeValidationCode.vorrundeNotConstant), isTrue);
    });

    test('a missing AdvanceAllEdge on a non-last round is an error', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.vorrunde,
        rounds: [_round(1, 4), _round(2, 4)],
        edges: const [],
      );
      final findings = validateStageTypeGraph(graph);
      expect(_hasCode(findings, TypeValidationCode.advanceAllMissing), isTrue);
    });

    test('a granular winner edge in a Vorrunde is forbidden', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.vorrunde,
        rounds: [_round(1, 4), _round(2, 4)],
        edges: const [
          AdvanceAllEdge(fromRound: 1, toRound: 2),
          WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'),
        ],
      );
      final findings = validateStageTypeGraph(graph);
      expect(
        _hasCode(findings, TypeValidationCode.vorrundeFieldEdgeForbidden),
        isTrue,
      );
    });
  });

  group('shared rules', () {
    test('an open path is a warning, not an error', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.ko,
        rounds: [_round(1, 2), _round(2, 1)],
        edges: const [
          WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'),
          WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'),
          OpenEdge(fromFieldId: 'R2F1', slot: OpenEdgeSlot.loser),
        ],
      );
      final findings = validateStageTypeGraph(graph);
      expect(_hasCode(findings, TypeValidationCode.openPath), isTrue);
      final open =
          findings.firstWhere((f) => f.code == TypeValidationCode.openPath);
      expect(open.severity, ValidationSeverity.warning);
      expect(hasTypeErrors(findings), isFalse);
    });

    test('an empty type graph is an error', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.ko,
        rounds: const [],
        edges: const [],
      );
      final findings = validateStageTypeGraph(graph);
      expect(_hasCode(findings, TypeValidationCode.emptyTypeGraph), isTrue);
    });

    test('a backward winner edge forms a cycle (error)', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.ko,
        rounds: [_round(1, 2), _round(2, 1)],
        edges: const [
          WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'),
          WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'),
          WinnerEdge(fromFieldId: 'R2F1', toFieldId: 'R1F1'),
        ],
      );
      final findings = validateStageTypeGraph(graph);
      expect(_hasCode(findings, TypeValidationCode.typeCycle), isTrue);
    });

    test('an edge to a non-existent field is an error', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.ko,
        rounds: [_round(1, 2), _round(2, 1)],
        edges: const [
          WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R9F9'),
        ],
      );
      final findings = validateStageTypeGraph(graph);
      expect(_hasCode(findings, TypeValidationCode.unknownTypeField), isTrue);
    });

    test('findings are stably ordered across two calls', () {
      final graph = StageTypeGraph(
        category: TypeStageCategory.vorrunde,
        rounds: [_round(1, 4), _round(2, 2)],
        edges: const [
          OpenEdge(fromFieldId: 'R1F1', slot: OpenEdgeSlot.winner),
          WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'),
        ],
      );
      expect(validateStageTypeGraph(graph), validateStageTypeGraph(graph));
    });
  });
}
