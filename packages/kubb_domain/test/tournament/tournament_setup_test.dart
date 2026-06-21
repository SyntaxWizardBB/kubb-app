import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('LeagueCategory', () {
    test('round-trips through its wire value', () {
      for (final c in LeagueCategory.values) {
        expect(LeagueCategory.fromWire(c.wire), c);
      }
    });

    test('rejects an unknown wire value', () {
      expect(() => LeagueCategory.fromWire('Z'), throwsArgumentError);
    });
  });

  group('VorrundeType', () {
    test('round-trips through its wire value', () {
      for (final v in VorrundeType.values) {
        expect(VorrundeType.fromWire(v.wire), v);
      }
    });

    test('rejects an unknown wire value', () {
      expect(() => VorrundeType.fromWire('bogus'), throwsArgumentError);
    });
  });

  group('KoType', () {
    test('round-trips through its wire value', () {
      for (final k in KoType.values) {
        expect(KoType.fromWire(k.wire), k);
      }
    });

    test('rejects an unknown wire value', () {
      expect(() => KoType.fromWire('bogus'), throwsArgumentError);
    });
  });

  group('MatchFormatSpec', () {
    const spec = MatchFormatSpec(
      setsToWin: 3,
      maxSets: 5,
      timeLimitSeconds: 3600,
      breakBetweenMatchesSeconds: 300,
      finalNoTiebreak: true,
    );

    test('tiebreakAfterSeconds derives from the match time when enabled', () {
      const enabled = MatchFormatSpec(
        setsToWin: 2,
        maxSets: 3,
        timeLimitSeconds: 1800,
      );
      // No separate offset: the tiebreak opens once the match time runs out.
      expect(enabled.tiebreakAfterSeconds, 1800);

      const disabled = MatchFormatSpec(
        setsToWin: 2,
        maxSets: 3,
        timeLimitSeconds: 1800,
        tiebreakEnabled: false,
      );
      expect(disabled.tiebreakAfterSeconds, isNull);
    });

    test('JSON round-trips with snake_case keys', () {
      final json = spec.toJson();
      expect(json['sets_to_win'], 3);
      // The tiebreak window is bound to the match end (= timeLimitSeconds).
      expect(json['tiebreak_after_seconds'], 3600);
      expect(json['final_no_tiebreak'], true);
      expect(MatchFormatSpec.fromJson(json), spec);
    });

    test('fromJson ignores the legacy tiebreak_after_seconds key', () {
      // Older rows still carry an explicit offset; it must not survive — the
      // trigger is derived from the match time now.
      final parsed = MatchFormatSpec.fromJson(const <String, Object?>{
        'sets_to_win': 2,
        'max_sets': 3,
        'time_limit_seconds': 1500,
        'tiebreak_after_seconds': 900,
      });
      expect(parsed.tiebreakEnabled, true);
      expect(parsed.tiebreakAfterSeconds, 1500);
      expect(parsed.basekubbsPerSide, 5);
      expect(parsed.finalNoTiebreak, false);
    });

    test('issues flags max_sets too small', () {
      const bad = MatchFormatSpec(
        setsToWin: 3,
        maxSets: 3,
        timeLimitSeconds: 3600,
      );
      final issues = bad.issues();
      expect(issues, isNotEmpty);
      expect(
        issues.any((i) => i.contains('Max. Sätze')),
        isTrue,
      );
    });

    test('issues is empty for a valid spec', () {
      expect(spec.issues(), isEmpty);
    });
  });

  group('RuleVariants', () {
    test('JSON round-trips', () {
      const rv = RuleVariants(
        sureshot: true,
        // Non-default (K05 default is true) so the round-trip covers it.
        diggy: false,
        strafkubbOffBaseline: false,
      );
      expect(RuleVariants.fromJson(rv.toJson()), rv);
    });

    test('defaults match the conservative Swiss ruleset', () {
      const rv = RuleVariants();
      expect(rv.sureshot, false);
      // K05: Diggy defaults to ON for new tournaments.
      expect(rv.diggy, true);
      expect(rv.openingRule, '2-4-6');
      expect(rv.strafkubbOffBaseline, true);
    });

    test('K05: diggy default is ON and fromJson falls back to true', () {
      expect(const RuleVariants().diggy, isTrue);
      expect(RuleVariants.fromJson(const <String, Object?>{}).diggy, isTrue);
      // An explicit false still round-trips.
      expect(
        RuleVariants.fromJson(const <String, Object?>{'diggy': false}).diggy,
        isFalse,
      );
    });
  });

  group('PitchPlan', () {
    test('range mode expands to the inclusive number list', () {
      const plan = PitchPlan(mode: PitchMode.range, rangeFrom: 10, rangeTo: 13);
      expect(plan.availablePitches(), <int>[10, 11, 12, 13]);
    });

    test('explicit order is honoured, extras appended', () {
      const plan = PitchPlan(
        mode: PitchMode.manual,
        numbers: <int>[5, 6, 7, 8],
        order: <int>[8, 5],
      );
      expect(plan.availablePitches(), <int>[8, 5, 6, 7]);
    });

    test('manual numbers are deduplicated, first occurrence wins', () {
      const plan = PitchPlan(
        mode: PitchMode.manual,
        numbers: <int>[3, 1, 3, 2, 1],
      );
      expect(plan.availablePitches(), <int>[3, 1, 2]);
    });

    test('JSON round-trips including group assignment', () {
      const plan = PitchPlan(
        mode: PitchMode.manual,
        numbers: <int>[1, 2, 3, 4],
        sortStrategy: PitchSortStrategy.manual,
        groupAssignment: <String, List<int>>{
          'A': <int>[1, 2],
          'B': <int>[3, 4],
        },
      );
      expect(PitchPlan.fromJson(plan.toJson()), plan);
    });

    test('issues flags an empty manual list and a bad range', () {
      const emptyManual = PitchPlan(mode: PitchMode.manual);
      expect(emptyManual.issues(), isNotEmpty);

      const badRange = PitchPlan(
        mode: PitchMode.range,
        rangeFrom: 10,
        rangeTo: 5,
      );
      expect(badRange.issues(), isNotEmpty);
    });

    test('copyWith overrides only the given fields, == stays consistent', () {
      const base = PitchPlan(
        mode: PitchMode.range,
        rangeFrom: 1,
        rangeTo: 4,
      );

      // No overrides => equal value (and equal hashCode).
      final clone = base.copyWith();
      expect(clone, base);
      expect(clone.hashCode, base.hashCode);

      // Override the group assignment only; other fields untouched.
      final assigned = base.copyWith(
        groupAssignment: <String, List<int>>{
          'A': <int>[1, 2],
          'B': <int>[3, 4],
        },
      );
      expect(assigned.mode, base.mode);
      expect(assigned.rangeFrom, base.rangeFrom);
      expect(assigned.rangeTo, base.rangeTo);
      expect(assigned.sortStrategy, base.sortStrategy);
      expect(assigned.groupAssignment, <String, List<int>>{
        'A': <int>[1, 2],
        'B': <int>[3, 4],
      });
      expect(assigned == base, isFalse);

      // Override the remaining fields and round-trip through ==.
      final full = base.copyWith(
        mode: PitchMode.manual,
        numbers: <int>[5, 6],
        order: <int>[6, 5],
        sortStrategy: PitchSortStrategy.manual,
      );
      const expected = PitchPlan(
        mode: PitchMode.manual,
        rangeFrom: 1,
        rangeTo: 4,
        numbers: <int>[5, 6],
        order: <int>[6, 5],
        sortStrategy: PitchSortStrategy.manual,
      );
      expect(full, expected);
      expect(full.hashCode, expected.hashCode);
    });
  });

  group('MightyFinisherQuali', () {
    test('defaults match decision §F (slots 6, group runners-up)', () {
      const q = MightyFinisherQuali();
      expect(q.enabled, false);
      expect(q.slots, 6);
      expect(q.pool, MightyFinisherPool.groupRunnersUp);
    });

    test('JSON round-trips', () {
      const q = MightyFinisherQuali(
        enabled: true,
        slots: 8,
        pool: MightyFinisherPool.rankBand,
      );
      expect(MightyFinisherQuali.fromJson(q.toJson()), q);
    });

    test('toJson uses the §F wire shape (method/pool/slots/tiebreak)', () {
      const q = MightyFinisherQuali(enabled: true);
      final json = q.toJson();
      expect(json['method'], 'mighty_finisher_shootout');
      expect(json['pool'], 'group_runners_up');
      expect(json['slots'], 6);
      expect(json['tiebreak'], 'eight_meter_sudden_death');
      // The legacy free-text `source` key must be gone.
      expect(json.containsKey('source'), isFalse);
    });

    test('fromJson defaults pool when absent and rejects unknown pool', () {
      final parsed = MightyFinisherQuali.fromJson(const <String, Object?>{
        'enabled': true,
        'slots': 4,
      });
      expect(parsed.pool, MightyFinisherPool.groupRunnersUp);
      expect(parsed.slots, 4);
      expect(
        () => MightyFinisherQuali.fromJson(
          const <String, Object?>{'pool': 'group_runner_ups'},
        ),
        throwsArgumentError,
      );
    });

    test('issues flags enabled with zero slots', () {
      const q = MightyFinisherQuali(enabled: true, slots: 0);
      expect(q.issues(), isNotEmpty);
    });
  });

  group('ConsolationConfig', () {
    test('defaults match decision §E (early KO losers source)', () {
      const c = ConsolationConfig();
      expect(c.enabled, false);
      expect(c.source, ConsolationSource.earlyKoLosers);
    });

    test('JSON round-trips early-ko-losers with a nested match format', () {
      const c = ConsolationConfig(
        enabled: true,
        sourceRounds: <int>[1, 2],
        matchFormat: MatchFormatSpec(
          setsToWin: 2,
          maxSets: 3,
          timeLimitSeconds: 1800,
        ),
      );
      final json = c.toJson();
      expect(json['source'], 'early_ko_losers');
      expect(json['source_rounds'], <int>[1, 2]);
      expect(ConsolationConfig.fromJson(json), c);
    });

    test('JSON round-trips prelim-rank-band with rank_from/rank_to', () {
      const c = ConsolationConfig(
        enabled: true,
        source: ConsolationSource.prelimRankBand,
        rankFrom: 17,
        rankTo: 24,
      );
      final json = c.toJson();
      expect(json['source'], 'prelim_rank_band');
      expect(json['rank_from'], 17);
      expect(json['rank_to'], 24);
      expect(ConsolationConfig.fromJson(json), c);
    });

    test('issues flags early-ko-losers without source rounds', () {
      const c = ConsolationConfig(enabled: true);
      expect(c.issues(), isNotEmpty);
    });

    test('issues flags prelim-rank-band without a valid band', () {
      const missing = ConsolationConfig(
        enabled: true,
        source: ConsolationSource.prelimRankBand,
      );
      expect(missing.issues(), isNotEmpty);

      const bad = ConsolationConfig(
        enabled: true,
        source: ConsolationSource.prelimRankBand,
        rankFrom: 24,
        rankTo: 17,
      );
      expect(bad.issues(), isNotEmpty);
    });

    test('fromJson rejects an unknown source token', () {
      expect(
        () => ConsolationConfig.fromJson(
          const <String, Object?>{'source': 'bogus'},
        ),
        throwsArgumentError,
      );
    });
  });
}
