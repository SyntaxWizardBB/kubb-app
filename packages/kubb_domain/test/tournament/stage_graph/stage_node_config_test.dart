import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('stage node config — KO', () {
    test('writeKoNodeConfig round-trips matchup / tiebreak / reset / formats',
        () {
      const formats = <MatchFormatSpec>[
        MatchFormatSpec(setsToWin: 1, maxSets: 1, timeLimitSeconds: 600),
        MatchFormatSpec(setsToWin: 2, maxSets: 3, timeLimitSeconds: 900),
      ];
      final config = writeKoNodeConfig(
        matchup: KoMatchup.oneVsTwo,
        tiebreakMethod: KoTiebreakMethod.mightyFinisherShootout,
        withReset: true,
        roundFormats: formats,
      );

      expect(koMatchupFromConfig(config), KoMatchup.oneVsTwo);
      expect(koTiebreakMethodFromConfig(config),
          KoTiebreakMethod.mightyFinisherShootout);
      expect(koWithResetFromConfig(config), isTrue);
      final read = koRoundFormatsFromConfig(config);
      expect(read, hasLength(2));
      expect(read[0].setsToWin, 1);
      expect(read[1].timeLimitSeconds, 900);
    });

    test('omits unset fields (no empty placeholder keys)', () {
      final config = writeKoNodeConfig(matchup: KoMatchup.seedHighVsLow);
      expect(config.containsKey(StageNodeConfigKeys.koTiebreakMethod), isFalse);
      expect(config.containsKey(StageNodeConfigKeys.withReset), isFalse);
      expect(config.containsKey(StageNodeConfigKeys.koRoundFormats), isFalse);
    });

    test('withReset:false is still written (explicit double-elim choice)', () {
      final config = writeKoNodeConfig(withReset: false);
      expect(config[StageNodeConfigKeys.withReset], isFalse);
      expect(koWithResetFromConfig(config), isFalse);
    });
  });

  group('stage node config — pool', () {
    test('writePoolNodeConfig round-trips group/qualifier/strategy/seed', () {
      final config = writePoolNodeConfig(
        groupCount: 4,
        qualifierCount: 2,
        strategy: PoolGroupingStrategy.random,
        randomSeed: 42,
      );
      expect(config[StageNodeConfigKeys.groupCount], 4);
      expect(config[StageNodeConfigKeys.qualifierCount], 2);
      expect(poolGroupingStrategyFromConfig(config), PoolGroupingStrategy.random);
      expect(poolRandomSeedFromConfig(config), 42);
    });

    test('omits strategy/seed when unset', () {
      final config = writePoolNodeConfig(groupCount: 2, qualifierCount: 1);
      expect(config.containsKey(StageNodeConfigKeys.groupingStrategy), isFalse);
      expect(config.containsKey(StageNodeConfigKeys.randomSeed), isFalse);
      expect(poolGroupingStrategyFromConfig(config), isNull);
    });
  });

  group('stage node config — readers are total (partial/garbage tolerant)', () {
    test('missing keys yield null/empty/false, never throw', () {
      const empty = <String, Object?>{};
      expect(koMatchupFromConfig(empty), isNull);
      expect(koTiebreakMethodFromConfig(empty), isNull);
      expect(koWithResetFromConfig(empty), isFalse);
      expect(koRoundFormatsFromConfig(empty), isEmpty);
      expect(poolGroupingStrategyFromConfig(empty), isNull);
      expect(poolRandomSeedFromConfig(empty), isNull);
    });

    test('wrong-typed / unknown values are ignored, not thrown', () {
      final garbage = <String, Object?>{
        StageNodeConfigKeys.koMatchup: 'not_a_matchup',
        StageNodeConfigKeys.koTiebreakMethod: 123,
        StageNodeConfigKeys.koRoundFormats: <Object?>[
          'bad',
          const MatchFormatSpec(setsToWin: 1, maxSets: 1, timeLimitSeconds: 600)
              .toJson(),
        ],
        StageNodeConfigKeys.groupingStrategy: 'nope',
        StageNodeConfigKeys.randomSeed: 'x',
      };
      expect(koMatchupFromConfig(garbage), isNull);
      expect(koTiebreakMethodFromConfig(garbage), isNull);
      // the one well-formed round survives; the 'bad' string is skipped.
      expect(koRoundFormatsFromConfig(garbage), hasLength(1));
      expect(poolGroupingStrategyFromConfig(garbage), isNull);
      expect(poolRandomSeedFromConfig(garbage), isNull);
    });
  });
}
