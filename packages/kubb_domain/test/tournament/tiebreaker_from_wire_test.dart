import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('tiebreakerCriterionFromWire', () {
    test('maps every canonical wire token to its criterion', () {
      expect(tiebreakerCriterionFromWire('total_points'),
          TiebreakerCriterion.totalPoints);
      expect(tiebreakerCriterionFromWire('wins'), TiebreakerCriterion.wins);
      expect(tiebreakerCriterionFromWire('kubb_difference'),
          TiebreakerCriterion.kubbDifference);
      expect(tiebreakerCriterionFromWire('buchholz'),
          TiebreakerCriterion.buchholz);
      expect(tiebreakerCriterionFromWire('buchholz_minus_h2h'),
          TiebreakerCriterion.buchholzMinusH2H);
      expect(tiebreakerCriterionFromWire('median_buchholz'),
          TiebreakerCriterion.medianBuchholz);
      expect(tiebreakerCriterionFromWire('direct_comparison'),
          TiebreakerCriterion.directComparison);
      expect(tiebreakerCriterionFromWire('mighty_finisher_shootout'),
          TiebreakerCriterion.mightyFinisherShootout);
      expect(tiebreakerCriterionFromWire('random'), TiebreakerCriterion.random);
    });

    test('accepts the kubb_diff alias as kubb difference', () {
      expect(tiebreakerCriterionFromWire('kubb_diff'),
          TiebreakerCriterion.kubbDifference);
    });

    test('accepts the shootout alias as mighty-finisher shoot-out', () {
      expect(tiebreakerCriterionFromWire('shootout'),
          TiebreakerCriterion.mightyFinisherShootout);
    });

    test('returns null for an unknown token instead of throwing', () {
      expect(tiebreakerCriterionFromWire('nonsense'), isNull);
      expect(tiebreakerCriterionFromWire(''), isNull);
    });
  });

  group('tiebreakerChainFromTokens', () {
    test('maps a full token list in order', () {
      expect(
        tiebreakerChainFromTokens(const [
          'total_points',
          'buchholz',
          'kubb_difference',
        ]),
        equals(const [
          TiebreakerCriterion.totalPoints,
          TiebreakerCriterion.buchholz,
          TiebreakerCriterion.kubbDifference,
        ]),
      );
    });

    test('drops unknown tokens but keeps the recognized ones in order', () {
      expect(
        tiebreakerChainFromTokens(const [
          'total_points',
          'garbage',
          'wins',
        ]),
        equals(const [
          TiebreakerCriterion.totalPoints,
          TiebreakerCriterion.wins,
        ]),
      );
    });

    test('falls back to the default chain for an empty token list', () {
      expect(
        tiebreakerChainFromTokens(const []),
        equals(defaultTiebreakerChain),
      );
    });

    test('falls back to the default chain when no token is recognized', () {
      expect(
        tiebreakerChainFromTokens(const ['nope', '???']),
        equals(defaultTiebreakerChain),
      );
    });

    test('default chain leads with total points', () {
      expect(defaultTiebreakerChain.first, TiebreakerCriterion.totalPoints);
    });
  });
}
