import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_domain/kubb_domain.dart';

void main() {
  group('TournamentConfigDraft', () {
    test('defaults match spec', () {
      const d = TournamentConfigDraft();
      expect(d.displayName, isNull);
      expect(d.teamSize, 1);
      expect(d.minParticipants, 2);
      expect(d.maxParticipants, 8);
      expect(d.format, TournamentFormat.roundRobin);
      expect(d.setsToWin, 2);
      expect(d.maxSets, 3);
      expect(d.roundTimeSeconds, 1800);
      expect(d.basekubbsPerSide, 5);
      expect(d.tiebreakerOrder, [
        'total_points',
        'buchholz_minus_h2h',
        'direct_comparison',
        'wins',
      ]);
      expect(d.koConfig, isNull);
      expect(d.bracketSeedingMode, isNull);
      expect(d.leagueEligible, isFalse);
    });

    test('copyWith replaces only provided fields', () {
      const d = TournamentConfigDraft();
      final updated = d.copyWith(displayName: 'Cup 2026', setsToWin: 3);
      expect(updated.displayName, 'Cup 2026');
      expect(updated.setsToWin, 3);
      expect(updated.minParticipants, 2);
      expect(updated.format, TournamentFormat.roundRobin);
    });

    test('value equality and hashCode line up for identical drafts', () {
      const a = TournamentConfigDraft(displayName: 'X');
      const b = TournamentConfigDraft(displayName: 'X');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('value equality differs when a field changes', () {
      const a = TournamentConfigDraft(displayName: 'X');
      const b = TournamentConfigDraft(displayName: 'X', setsToWin: 3);
      expect(a, isNot(equals(b)));
    });
  });

  group('TournamentConfigDraft.validate', () {
    test('valid for a fully filled draft', () {
      const d = TournamentConfigDraft(displayName: 'Cup 2026');
      final v = d.validate();
      expect(v.isValid, isTrue);
      expect(v.issues, isEmpty);
    });

    test('flags empty display name', () {
      const d = TournamentConfigDraft(displayName: '   ');
      final v = d.validate();
      expect(v.isValid, isFalse);
      expect(v.issues.any((i) => i.contains('Turniername')), isTrue);
    });

    test('flags too short display name', () {
      const d = TournamentConfigDraft(displayName: 'AB');
      final v = d.validate();
      expect(v.isValid, isFalse);
      expect(v.issues.any((i) => i.contains('Zeichen')), isTrue);
    });

    test('flags too long display name', () {
      final d = TournamentConfigDraft(displayName: 'A' * 100);
      final v = d.validate();
      expect(v.isValid, isFalse);
      expect(v.issues.any((i) => i.contains('höchstens')), isTrue);
    });

    test('flags min > max participants', () {
      const d = TournamentConfigDraft(
        displayName: 'Cup',
        minParticipants: 10,
        maxParticipants: 4,
      );
      final v = d.validate();
      expect(v.isValid, isFalse);
      expect(
        v.issues.any((i) => i.contains('grösser') || i.contains('Min')),
        isTrue,
      );
    });

    test('flags sets-to-win below 1', () {
      const d = TournamentConfigDraft(
        displayName: 'Cup',
        setsToWin: 0,
      );
      final v = d.validate();
      expect(v.isValid, isFalse);
      expect(v.issues.any((i) => i.contains('Sätze zum Sieg')), isTrue);
    });

    test('flags max_sets too small for the configured sets_to_win', () {
      const d = TournamentConfigDraft(
        displayName: 'Cup',
        setsToWin: 3,
      );
      final v = d.validate();
      expect(v.isValid, isFalse);
      expect(v.issues.any((i) => i.contains('Max. Sätze')), isTrue);
    });
  });

  group('TournamentConfigDraft KO fields', () {
    final ko = KoPhaseConfig(qualifierCount: 4, participantCount: 8);

    test('copyWith carries koConfig, seedingMode and leagueEligible', () {
      const d = TournamentConfigDraft(displayName: 'Cup');
      final updated = d.copyWith(
        koConfig: ko,
        bracketSeedingMode: SeedingMode.manual,
        leagueEligible: true,
      );
      expect(updated.koConfig, same(ko));
      expect(updated.bracketSeedingMode, SeedingMode.manual);
      expect(updated.leagueEligible, isTrue);
    });

    test('equality covers koConfig, seedingMode and leagueEligible', () {
      final a = TournamentConfigDraft(
        displayName: 'Cup',
        koConfig: ko,
        bracketSeedingMode: SeedingMode.auto,
        leagueEligible: true,
      );
      final b = TournamentConfigDraft(
        displayName: 'Cup',
        koConfig: KoPhaseConfig(qualifierCount: 4, participantCount: 8),
        bracketSeedingMode: SeedingMode.auto,
        leagueEligible: true,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);

      final c = a.copyWith(leagueEligible: false);
      expect(a, isNot(equals(c)));
    });

    test('validate flags missing koConfig for single_elimination', () {
      const d = TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.singleElimination,
      );
      final v = d.validate();
      expect(v.isValid, isFalse);
      expect(v.issues.any((i) => i.contains('KO-Phase')), isTrue);
    });

    test('validate flags missing koConfig for round_robin_then_ko', () {
      const d = TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.roundRobinThenKo,
      );
      final v = d.validate();
      expect(v.isValid, isFalse);
      expect(v.issues.any((i) => i.contains('KO-Phase')), isTrue);
    });

    test('validate passes when koConfig set for single_elimination', () {
      final d = TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.singleElimination,
        koConfig: ko,
      );
      final v = d.validate();
      expect(v.isValid, isTrue);
      expect(v.issues, isEmpty);
    });

    test('validate ignores koConfig for round_robin', () {
      const d = TournamentConfigDraft(displayName: 'Cup');
      final v = d.validate();
      expect(v.isValid, isTrue);
    });

    test('suggestedWithThirdPlacePlayoff follows leagueEligible', () {
      const off = TournamentConfigDraft(displayName: 'Cup');
      expect(off.suggestedWithThirdPlacePlayoff, isFalse);

      const on = TournamentConfigDraft(
        displayName: 'Cup',
        leagueEligible: true,
      );
      expect(on.suggestedWithThirdPlacePlayoff, isTrue);
    });
  });

  group('TournamentConfigDraft.toMatchFormatConfig', () {
    test('maps to the snake_case wire shape the RPC expects', () {
      const d = TournamentConfigDraft(
        displayName: 'Cup',
        setsToWin: 3,
        maxSets: 5,
        roundTimeSeconds: 1200,
        basekubbsPerSide: 6,
      );
      expect(d.toMatchFormatConfig(), <String, Object?>{
        'sets_to_win': 3,
        'max_sets': 5,
        'round_time_seconds': 1200,
        'basekubbs_per_side': 6,
      });
    });
  });

  group('TournamentConfigDraft.toSetupConfig', () {
    test('emits defaults: CHF currency, ekc scoring, empty lists', () {
      const d = TournamentConfigDraft();
      final setup = d.toSetupConfig();
      expect(setup['currency'], 'CHF');
      expect(setup['scoring'], 'ekc');
      expect(setup['payment_methods'], isEmpty);
      expect(setup['league_categories'], isEmpty);
      expect(setup['location'], isNull);
      expect(setup['ko_match_format'], isNull);
      expect(setup['pitch_plan'], isNull);
      expect(setup['rule_variants'], isA<Map<String, Object?>>());
    });

    test('serialises P6 fields into the snake_case wire shape', () {
      final d = TournamentConfigDraft(
        displayName: 'Bâton',
        location: 'Brugg',
        venueAddress: 'P3 Geissenschachen',
        eventStartsAt: DateTime.utc(2026, 6, 19, 18, 30),
        registrationClosesAt: DateTime.utc(2026, 6, 18, 23, 59),
        entryFeeCents: 1000,
        paymentMethods: const <String>['cash', 'twint'],
        leagueCategories: const <LeagueCategory>[
          LeagueCategory.a,
          LeagueCategory.b,
        ],
        scoring: 'classic',
        ruleVariants: const RuleVariants(diggy: true),
        koMatchFormat: const MatchFormatSpec(
          setsToWin: 3,
          maxSets: 5,
          timeLimitSeconds: 3600,
          tiebreakAfterSeconds: 2400,
          finalNoTiebreak: true,
        ),
        pitchPlan: const PitchPlan(
          mode: PitchMode.range,
          rangeFrom: 10,
          rangeTo: 20,
        ),
      );
      final setup = d.toSetupConfig();
      expect(setup['location'], 'Brugg');
      expect(setup['venue_address'], 'P3 Geissenschachen');
      expect(setup['event_starts_at'], '2026-06-19T18:30:00.000Z');
      expect(setup['registration_closes_at'], '2026-06-18T23:59:00.000Z');
      expect(setup['entry_fee_cents'], 1000);
      expect(setup['payment_methods'], <String>['cash', 'twint']);
      expect(setup['league_categories'], <String>['A', 'B']);
      expect(setup['scoring'], 'classic');
      expect(
        (setup['rule_variants']! as Map<String, Object?>)['diggy'],
        true,
      );
      expect(
        (setup['ko_match_format']! as Map<String, Object?>)['final_no_tiebreak'],
        true,
      );
      expect(
        (setup['pitch_plan']! as Map<String, Object?>)['mode'],
        'range',
      );
    });

    test('serialises participation, info, rule variants and PDF URLs', () {
      const d = TournamentConfigDraft(
        entryFeeCents: 1000,
        paymentMethods: <String>['cash', 'twint'],
        contactName: 'Yves',
        contactPhone: '079 347 18 35',
        infoFood: 'Bratwurst & Bier',
        weatherNote: 'Findet bei jedem Wetter statt',
        ruleVariants: RuleVariants(sureshot: true, diggy: true),
        rulesPdfUrl: 'https://x/rules.pdf',
        siteMapPdfUrl: 'https://x/map.pdf',
      );
      final setup = d.toSetupConfig();
      expect(setup['entry_fee_cents'], 1000);
      expect(setup['payment_methods'], <String>['cash', 'twint']);
      expect(setup['contact_name'], 'Yves');
      expect(setup['contact_phone'], '079 347 18 35');
      expect(setup['info_food'], 'Bratwurst & Bier');
      expect(setup['weather_note'], 'Findet bei jedem Wetter statt');
      expect((setup['rule_variants']! as Map<String, Object?>)['sureshot'],
          true);
      expect(setup['rules_pdf_url'], 'https://x/rules.pdf');
      expect(setup['site_map_pdf_url'], 'https://x/map.pdf');
    });

    test('blank text fields are nulled out in the payload', () {
      const d = TournamentConfigDraft(location: '   ', contactName: '');
      final setup = d.toSetupConfig();
      expect(setup['location'], isNull);
      expect(setup['contact_name'], isNull);
    });
  });
}
