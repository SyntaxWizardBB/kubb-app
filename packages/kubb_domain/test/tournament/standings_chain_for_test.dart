import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('standingsChainFor — group phase', () {
    test('ranks on points then kubb difference, never Buchholz', () {
      final chain = standingsChainFor(StageNodeType.groupPhase, const []);
      expect(chain.order.first, TiebreakerCriterion.totalPoints);
      expect(chain.order, contains(TiebreakerCriterion.kubbDifference));
      expect(
        chain.order,
        isNot(anyElement(isIn(const [
          TiebreakerCriterion.buchholz,
          TiebreakerCriterion.buchholzMinusH2H,
          TiebreakerCriterion.medianBuchholz,
        ]))),
      );
    });

    test('drops a configured Buchholz token in a group phase', () {
      final chain = standingsChainFor(
        StageNodeType.groupPhase,
        const ['total_points', 'buchholz', 'kubb_difference'],
      );
      expect(chain.order, isNot(contains(TiebreakerCriterion.buchholz)));
      expect(chain.order, contains(TiebreakerCriterion.kubbDifference));
    });

    test('falls back to the fixed group chain when the config is empty', () {
      final chain = standingsChainFor(StageNodeType.groupPhase, const []);
      expect(
        chain.order,
        equals(chainForStageType(StageNodeType.groupPhase).order),
      );
    });
  });

  group('standingsChainFor — schoch', () {
    test('puts Buchholz second after points', () {
      final chain = standingsChainFor(StageNodeType.schoch, const []);
      expect(chain.order.first, TiebreakerCriterion.totalPoints);
      expect(chain.order, contains(TiebreakerCriterion.buchholz));
      expect(chain.order, isNot(contains(TiebreakerCriterion.kubbDifference)));
    });

    test('drops the naive buchholz_minus_h2h in favour of the §5 buchholz', () {
      final chain = standingsChainFor(
        StageNodeType.schoch,
        const ['total_points', 'buchholz_minus_h2h'],
      );
      expect(chain.order, isNot(contains(TiebreakerCriterion.buchholzMinusH2H)));
      expect(chain.order, contains(TiebreakerCriterion.buchholz));
    });

    test('falls back to the fixed schoch chain when the config is empty', () {
      final chain = standingsChainFor(StageNodeType.schoch, const []);
      expect(
        chain.order,
        equals(chainForStageType(StageNodeType.schoch).order),
      );
    });
  });

  group('standingsChainFor — round robin', () {
    test('ranks on points then kubb difference, no Buchholz', () {
      final chain = standingsChainFor(StageNodeType.roundRobin, const []);
      expect(chain.order.first, TiebreakerCriterion.totalPoints);
      expect(chain.order, contains(TiebreakerCriterion.kubbDifference));
      expect(chain.order, isNot(contains(TiebreakerCriterion.buchholz)));
    });

    test('honours a configured order while dropping Buchholz', () {
      final chain = standingsChainFor(
        StageNodeType.roundRobin,
        const ['total_points', 'wins', 'buchholz', 'kubb_difference'],
      );
      expect(
        chain.order,
        equals(const [
          TiebreakerCriterion.totalPoints,
          TiebreakerCriterion.wins,
          TiebreakerCriterion.kubbDifference,
        ]),
      );
    });
  });

  group('standingsChainFor — bracket stages', () {
    test('single elimination falls back to the default chain', () {
      final chain = standingsChainFor(StageNodeType.singleElim, const []);
      expect(chain.order, equals(defaultTiebreakerChain));
    });

    test('respects a configured order for a bracket stage', () {
      final chain = standingsChainFor(
        StageNodeType.singleElim,
        const ['total_points', 'wins'],
      );
      expect(
        chain.order,
        equals(const [
          TiebreakerCriterion.totalPoints,
          TiebreakerCriterion.wins,
        ]),
      );
    });
  });
}
