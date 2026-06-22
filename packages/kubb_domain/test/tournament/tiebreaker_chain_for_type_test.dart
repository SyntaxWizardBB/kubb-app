import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('chainForStageType', () {
    test('group phase ranks on kubb difference, never Buchholz', () {
      final chain = chainForStageType(StageNodeType.groupPhase);
      expect(
        chain.order,
        equals(const [
          TiebreakerCriterion.totalPoints,
          TiebreakerCriterion.kubbDifference,
          TiebreakerCriterion.mightyFinisherShootout,
        ]),
      );
      expect(chain.order, contains(TiebreakerCriterion.kubbDifference));
      expect(
        chain.order,
        isNot(anyElement(isIn(const [
          TiebreakerCriterion.buchholz,
          TiebreakerCriterion.buchholzMinusH2H,
          TiebreakerCriterion.medianBuchholz,
          TiebreakerCriterion.directComparison,
        ]))),
      );
    });

    test('schoch puts Buchholz second', () {
      final chain = chainForStageType(StageNodeType.schoch);
      expect(
        chain.order,
        equals(const [
          TiebreakerCriterion.totalPoints,
          TiebreakerCriterion.buchholz,
          TiebreakerCriterion.mightyFinisherShootout,
        ]),
      );
      expect(chain.order[1], equals(TiebreakerCriterion.buchholz));
      expect(chain.order, isNot(contains(TiebreakerCriterion.kubbDifference)));
    });

    test('schoch uses the §5 Buchholz, not the naive buchholzMinusH2H', () {
      final chain = chainForStageType(StageNodeType.schoch);
      expect(chain.order, isNot(contains(TiebreakerCriterion.buchholzMinusH2H)));
      expect(chain.order, isNot(contains(TiebreakerCriterion.medianBuchholz)));
    });

    test('a non-preliminary stage type throws instead of silently defaulting',
        () {
      expect(
        () => chainForStageType(StageNodeType.singleElim),
        throwsArgumentError,
      );
      expect(
        () => chainForStageType(StageNodeType.roundRobin),
        throwsArgumentError,
      );
      expect(
        () => chainForStageType(StageNodeType.consolation),
        throwsArgumentError,
      );
    });
  });
}
