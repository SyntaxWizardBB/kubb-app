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

    test('group pitch assignment round-trips through config serialization', () {
      final config = writePoolNodeConfig(
        groupCount: 2,
        qualifierCount: 2,
        groupPitchAssignment: const <String, List<int>>{
          'A': <int>[1, 2],
          'B': <int>[3],
        },
      );
      expect(poolGroupPitchAssignmentFromConfig(config), <String, List<int>>{
        'A': <int>[1, 2],
        'B': <int>[3],
      });
    });

    test('omits group pitch assignment when empty (no placeholder key)', () {
      final config = writePoolNodeConfig(groupCount: 2, qualifierCount: 1);
      expect(
        config.containsKey(StageNodeConfigKeys.groupPitchAssignment),
        isFalse,
      );
      expect(poolGroupPitchAssignmentFromConfig(config), isEmpty);
    });
  });

  group('stage node config — schoch', () {
    test('writeSchochNodeConfig round-trips the round count', () {
      final config = writeSchochNodeConfig(rounds: 8);
      expect(config[StageNodeConfigKeys.rounds], 8);
      expect(schochRoundsFromConfig(config), 8);
    });

    test('reader falls back to the default when the key is missing', () {
      expect(schochRoundsFromConfig(const <String, Object?>{}),
          defaultSchochRounds);
    });

    test('reader falls back to the default for a non-int / non-positive value',
        () {
      expect(
        schochRoundsFromConfig(const <String, Object?>{'rounds': 'seven'}),
        defaultSchochRounds,
      );
      expect(
        schochRoundsFromConfig(const <String, Object?>{'rounds': 0}),
        defaultSchochRounds,
      );
    });

    test('reader stays consistent with the stage-validation read (rounds + 1)',
        () {
      // _minInputForNode reads a positive int and uses rounds + 1; the helper
      // must surface the same positive int so the two never drift.
      final config = writeSchochNodeConfig(rounds: 5);
      expect(schochRoundsFromConfig(config), 5);
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
      expect(poolGroupPitchAssignmentFromConfig(empty), isEmpty);
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
        StageNodeConfigKeys.groupPitchAssignment: <Object?, Object?>{
          'A': <Object?>[1, 'x', 2],
          7: <Object?>[3],
          'B': 'not_a_list',
        },
      };
      expect(koMatchupFromConfig(garbage), isNull);
      expect(koTiebreakMethodFromConfig(garbage), isNull);
      // the one well-formed round survives; the 'bad' string is skipped.
      expect(koRoundFormatsFromConfig(garbage), hasLength(1));
      expect(poolGroupingStrategyFromConfig(garbage), isNull);
      expect(poolRandomSeedFromConfig(garbage), isNull);
      // non-int pitches dropped, non-string key dropped, non-list value dropped.
      expect(poolGroupPitchAssignmentFromConfig(garbage), <String, List<int>>{
        'A': <int>[1, 2],
      });
    });
  });
}
