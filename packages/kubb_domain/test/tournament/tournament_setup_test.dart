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

  group('MatchFormatSpec', () {
    const spec = MatchFormatSpec(
      setsToWin: 3,
      maxSets: 5,
      timeLimitSeconds: 3600,
      tiebreakAfterSeconds: 2400,
      breakBetweenMatchesSeconds: 300,
      finalNoTiebreak: true,
    );

    test('JSON round-trips with snake_case keys', () {
      final json = spec.toJson();
      expect(json['sets_to_win'], 3);
      expect(json['tiebreak_after_seconds'], 2400);
      expect(json['final_no_tiebreak'], true);
      expect(MatchFormatSpec.fromJson(json), spec);
    });

    test('fromJson applies defaults for optional keys', () {
      final parsed = MatchFormatSpec.fromJson(const <String, Object?>{
        'sets_to_win': 2,
        'max_sets': 3,
        'time_limit_seconds': 1500,
      });
      expect(parsed.tiebreakEnabled, true);
      expect(parsed.tiebreakAfterSeconds, isNull);
      expect(parsed.basekubbsPerSide, 5);
      expect(parsed.finalNoTiebreak, false);
    });

    test('issues flags max_sets too small and bad tiebreak time', () {
      const bad = MatchFormatSpec(
        setsToWin: 3,
        maxSets: 3,
        timeLimitSeconds: 3600,
        tiebreakAfterSeconds: 4000,
      );
      final issues = bad.issues();
      expect(issues, isNotEmpty);
      expect(
        issues.any((i) => i.contains('Max. Sätze')),
        isTrue,
      );
      expect(
        issues.any((i) => i.contains('Tiebreak-Zeit')),
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
        diggy: true,
        strafkubbOffBaseline: false,
      );
      expect(RuleVariants.fromJson(rv.toJson()), rv);
    });

    test('defaults match the conservative Swiss ruleset', () {
      const rv = RuleVariants();
      expect(rv.sureshot, false);
      expect(rv.diggy, false);
      expect(rv.openingRule, '2-4-6');
      expect(rv.strafkubbOffBaseline, true);
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
  });

  group('MightyFinisherQuali', () {
    test('JSON round-trips', () {
      const q = MightyFinisherQuali(enabled: true, slots: 6);
      expect(MightyFinisherQuali.fromJson(q.toJson()), q);
    });

    test('issues flags enabled with zero slots', () {
      const q = MightyFinisherQuali(enabled: true);
      expect(q.issues(), isNotEmpty);
    });
  });

  group('ConsolationConfig', () {
    test('JSON round-trips with a nested match format', () {
      const c = ConsolationConfig(
        enabled: true,
        sourceRounds: <int>[1, 2],
        matchFormat: MatchFormatSpec(
          setsToWin: 2,
          maxSets: 3,
          timeLimitSeconds: 1800,
        ),
      );
      expect(ConsolationConfig.fromJson(c.toJson()), c);
    });

    test('issues flags enabled without source rounds', () {
      const c = ConsolationConfig(enabled: true);
      expect(c.issues(), isNotEmpty);
    });
  });
}
