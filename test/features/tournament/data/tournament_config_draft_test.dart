import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// A draft that passes the (now stricter) Stammdaten validation: name,
/// club/Spasstournier choice and the required Stammdaten fields are all set.
/// Used by tests that assert `validate().isValid == true` for non-Stammdaten
/// concerns. Defaults to a Spasstournier (no club) so no league category is
/// required (K29). Override individual fields via copyWith.
TournamentConfigDraft _validStammdaten({String name = 'Cup'}) {
  final now = DateTime(2026, 8, 1, 10);
  return TournamentConfigDraft(
    displayName: name,
    clubChoiceMade: true,
    location: 'Esp',
    venueAddress: 'Sportplatz Esp, Fislisbach',
    eventStartsAt: now,
    registrationClosesAt: now.subtract(const Duration(days: 7)),
    checkinUntil: now.subtract(const Duration(minutes: 30)),
  );
}

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
        'mighty_finisher_shootout',
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
      final d = _validStammdaten(name: 'Cup 2026');
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

    test('accepts an even prelim max_sets (decoupled from sets_to_win)', () {
      // P6: the prelim allows draws, so max_sets=2 (an even value, no longer
      // tied to 2*setsToWin-1) must validate.
      final d = _validStammdaten().copyWith(maxSets: 2);
      final v = d.validate();
      expect(v.isValid, isTrue);
      expect(v.issues, isEmpty);
    });

    test('flags a prelim max_sets outside the absolute range', () {
      const tooHigh = TournamentConfigDraft(displayName: 'Cup', maxSets: 99);
      expect(tooHigh.validate().isValid, isFalse);
      const tooLow = TournamentConfigDraft(displayName: 'Cup', maxSets: 0);
      expect(tooLow.validate().isValid, isFalse);
    });

    // K03: club/Spasstournier choice is required.
    test('flags a missing club choice (K03)', () {
      expect(_validStammdaten().validate().isValid, isTrue);
      final notChosen =
          _validStammdaten().copyWith(clubChoiceMade: false);
      final v = notChosen.validate();
      expect(v.isValid, isFalse);
      expect(
        v.issues.any((i) => i.contains('Spasstournier') || i.contains('Verein')),
        isTrue,
      );
    });

    // K29: league category required when a club is chosen, exempt otherwise.
    test('flags missing league category when a club is set (K29)', () {
      final withClub = _validStammdaten().copyWith(clubId: 'club-1');
      final v = withClub.validate();
      expect(v.isValid, isFalse);
      expect(v.issues.any((i) => i.contains('Liga-Kategorie')), isTrue);

      final withCategory = withClub.copyWith(
        leagueCategories: const <LeagueCategory>[LeagueCategory.a],
      );
      expect(
        withCategory.validate().issues.any((i) => i.contains('Liga-Kategorie')),
        isFalse,
      );

      // Spasstournier (no club) is exempt from the league requirement.
      final funTournament = _validStammdaten();
      expect(
        funTournament.validate().issues.any((i) => i.contains('Liga-Kategorie')),
        isFalse,
      );
    });

    // K30/K31: location + address required.
    test('flags missing location and address (K30/K31)', () {
      final noLocation = _validStammdaten().copyWith(location: '   ');
      expect(noLocation.validate().issues.any((i) => i.contains('Ort')), isTrue);
      final noAddress = _validStammdaten().copyWith(venueAddress: '');
      expect(
        noAddress.validate().issues.any((i) => i.contains('Adresse')),
        isTrue,
      );
    });

    // K32/K33: start, registration deadline, check-in required.
    test('flags missing start / deadlines (K32/K33)', () {
      expect(_validStammdaten().validate().isValid, isTrue);
      // No copyWith null-clear for dates exists, so build a minimal draft.
      const noStart = TournamentConfigDraft(
        displayName: 'Cup',
        clubChoiceMade: true,
        location: 'X',
        venueAddress: 'Y',
      );
      final iss = noStart.validate().issues;
      expect(iss.any((i) => i.contains('Turnierstart')), isTrue);
      expect(iss.any((i) => i.contains('Anmeldeschluss')), isTrue);
      expect(iss.any((i) => i.contains('Check-in')), isTrue);
    });

    // K01: the displayName max-length check excludes the auto year suffix —
    // a name at the limit stays valid (resolvedDisplayName may overflow).
    test('name at the max length still validates (year suffix exempt, K01)',
        () {
      final d = _validStammdaten(
        name: 'A' * TournamentConfigDraft.displayNameMaxChars,
      );
      expect(d.validate().isValid, isTrue);
    });
  });

  group('TournamentConfigDraft.resolvedDisplayName (K01)', () {
    test('appends the current year when no year is present', () {
      final year = DateTime.now().year;
      const d = TournamentConfigDraft(displayName: 'Sommercup');
      expect(d.resolvedDisplayName, 'Sommercup $year');
    });

    test('appends the event-start year when set', () {
      final d = TournamentConfigDraft(
        displayName: 'Sommercup',
        eventStartsAt: DateTime(2027, 5, 20),
      );
      expect(d.resolvedDisplayName, 'Sommercup 2027');
    });

    test('is idempotent: an existing 4-digit year is not re-appended', () {
      const d = TournamentConfigDraft(displayName: 'Sommercup 2026');
      expect(d.resolvedDisplayName, 'Sommercup 2026');
      const d2 = TournamentConfigDraft(displayName: '2025 Winter Open');
      expect(d2.resolvedDisplayName, '2025 Winter Open');
    });

    test('returns null/empty unchanged', () {
      const d = TournamentConfigDraft();
      expect(d.resolvedDisplayName, isNull);
    });
  });

  group('TournamentConfigDraft rating relevance (K02)', () {
    test('Spasstournier (no club) is not rated and emits no league categories',
        () {
      final d = _validStammdaten();
      expect(d.clubId, isNull);
      expect(d.isRated, isFalse);
      final setup = d.toSetupConfig();
      expect(setup['league_categories'], isEmpty);
    });

    test('a club tournament is rated', () {
      final d = _validStammdaten().copyWith(
        clubId: 'club-1',
        leagueCategories: const <LeagueCategory>[LeagueCategory.a],
      );
      expect(d.isRated, isTrue);
      expect(d.toSetupConfig()['league_categories'], <String>['A']);
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
      final d = _validStammdaten().copyWith(
        format: TournamentFormat.singleElimination,
        koConfig: ko,
      );
      final v = d.validate();
      expect(v.isValid, isTrue);
      expect(v.issues, isEmpty);
    });

    test('validate ignores koConfig for round_robin', () {
      final d = _validStammdaten();
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
        'tiebreak_enabled': false,
        'tiebreak_after_seconds': null,
        'break_between_matches_seconds': 0,
      });
    });

    test('toMatchFormatConfig carries prelim tiebreak + break when set', () {
      const d = TournamentConfigDraft(
        roundTimeSeconds: 1500,
        prelimTiebreakAfterSeconds: 1200,
        breakBetweenMatchesSeconds: 300,
      );
      final cfg = d.toMatchFormatConfig();
      expect(cfg['tiebreak_enabled'], true);
      expect(cfg['tiebreak_after_seconds'], 1200);
      expect(cfg['break_between_matches_seconds'], 300);
    });

    test('validate flags a prelim tiebreak time above the limit', () {
      const d = TournamentConfigDraft(
        displayName: 'Cup',
        roundTimeSeconds: 1500,
        prelimTiebreakAfterSeconds: 2000,
      );
      final result = d.validate();
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.contains('Tiebreak-Zeit')),
        isTrue,
      );
    });
  });

  group('TournamentConfigDraft.schochSinglePoolConfig', () {
    test('builds a single pool that advances the KO qualifier count', () {
      final cfg = TournamentConfigDraft.schochSinglePoolConfig(
        KoPhaseConfig(qualifierCount: 8, participantCount: 16),
      );
      expect(cfg.groupCount, 1);
      expect(cfg.qualifiersPerGroup, 8);
      expect(cfg.strategy, PoolGroupingStrategy.seeded);
    });

    test('falls back to 2 qualifiers when the KO config is unknown', () {
      final cfg = TournamentConfigDraft.schochSinglePoolConfig(null);
      expect(cfg.groupCount, 1);
      expect(cfg.qualifiersPerGroup, 2);
    });
  });

  group('TournamentConfigDraft two-axis format mapping', () {
    test('formatFor maps every Vorrunde × KO combo to its hybrid format', () {
      // Every tournament has a KO stage, so a prelim always maps to its
      // hybrid (…ThenKo) format regardless of the KO type.
      expect(
        TournamentConfigDraft.formatFor(
            VorrundeType.groupPhase, KoType.singleOut),
        TournamentFormat.roundRobinThenKo,
      );
      expect(
        TournamentConfigDraft.formatFor(
            VorrundeType.groupPhase, KoType.doubleOut),
        TournamentFormat.roundRobinThenKo,
      );
      expect(
        TournamentConfigDraft.formatFor(
            VorrundeType.groupPhase, KoType.consolation),
        TournamentFormat.roundRobinThenKo,
      );
      expect(
        TournamentConfigDraft.formatFor(VorrundeType.schoch, KoType.singleOut),
        TournamentFormat.swissThenKo,
      );
      expect(
        TournamentConfigDraft.formatFor(VorrundeType.schoch, KoType.doubleOut),
        TournamentFormat.swissThenKo,
      );
      expect(
        TournamentConfigDraft.formatFor(
            VorrundeType.schoch, KoType.consolation),
        TournamentFormat.swissThenKo,
      );
    });

    test('bracketTypeFor reflects the KO single/double/consolation choice', () {
      expect(TournamentConfigDraft.bracketTypeFor(KoType.singleOut),
          BracketType.singleElimination);
      expect(TournamentConfigDraft.bracketTypeFor(KoType.doubleOut),
          BracketType.doubleElimination);
      // Consolation rides on a single-elimination main bracket (ADR-0028).
      expect(TournamentConfigDraft.bracketTypeFor(KoType.consolation),
          BracketType.singleElimination);
    });

    test('derived getters expose format + bracketType from the axes', () {
      const d = TournamentConfigDraft(
        vorrundeType: VorrundeType.schoch,
        koType: KoType.doubleOut,
      );
      expect(d.derivedFormat, TournamentFormat.swissThenKo);
      expect(d.derivedBracketType, BracketType.doubleElimination);
    });

    test('koRoundCountFor is ceil(log2(n))', () {
      expect(TournamentConfigDraft.koRoundCountFor(1), 0);
      expect(TournamentConfigDraft.koRoundCountFor(2), 1);
      expect(TournamentConfigDraft.koRoundCountFor(4), 2);
      expect(TournamentConfigDraft.koRoundCountFor(6), 3);
      expect(TournamentConfigDraft.koRoundCountFor(8), 3);
      expect(TournamentConfigDraft.koRoundCountFor(16), 4);
    });

    test('defaultKoRoundFormatFor follows the §A profile from the back', () {
      // 3-round bracket (Viertelfinale, Halbfinale, Final).
      final quarter = TournamentConfigDraft.defaultKoRoundFormatFor(0, 3);
      final semi = TournamentConfigDraft.defaultKoRoundFormatFor(1, 3);
      final fin = TournamentConfigDraft.defaultKoRoundFormatFor(2, 3);
      // Quarter: Bo5 with a 40-min tiebreak.
      expect(quarter.setsToWin, 3);
      expect(quarter.tiebreakEnabled, isTrue);
      expect(quarter.tiebreakAfterSeconds, 2400);
      // Semifinal: Bo5, no tiebreak.
      expect(semi.setsToWin, 3);
      expect(semi.tiebreakEnabled, isFalse);
      // Final: Bo5, no tiebreak, finalNoTiebreak.
      expect(fin.tiebreakEnabled, isFalse);
      expect(fin.finalNoTiebreak, isTrue);
      // Early round in a large bracket → Bo3 with a 25-min tiebreak.
      final early = TournamentConfigDraft.defaultKoRoundFormatFor(0, 5);
      expect(early.setsToWin, 2);
      expect(early.maxSets, 3);
      expect(early.tiebreakAfterSeconds, 1500);
    });

    test('withResizedKoRoundFormats grows, seeds and trims', () {
      final ko = KoPhaseConfig(qualifierCount: 8, participantCount: 16);
      const seed = MatchFormatSpec(
        setsToWin: 3,
        maxSets: 5,
        timeLimitSeconds: 3600,
      );
      final grown = TournamentConfigDraft(
        koConfig: ko,
        koMatchFormat: seed,
      ).withResizedKoRoundFormats();
      // 8 qualifiers => 3 KO rounds, all seeded from koMatchFormat.
      expect(grown.koRoundFormats, hasLength(3));
      expect(grown.koRoundFormats.every((f) => f == seed), isTrue);

      // Shrink to 2 qualifiers => 1 round, preserving the first entry.
      final shrunk = grown
          .copyWith(
            koConfig: KoPhaseConfig(qualifierCount: 2, participantCount: 16),
          )
          .withResizedKoRoundFormats();
      expect(shrunk.koRoundFormats, hasLength(1));
      expect(shrunk.koRoundFormats.first, seed);
    });

    test('withResizedKoRoundFormats falls back to the default seed', () {
      final ko = KoPhaseConfig(qualifierCount: 4, participantCount: 8);
      final d = TournamentConfigDraft(koConfig: ko)
          .withResizedKoRoundFormats();
      expect(d.koRoundFormats, hasLength(2));
      expect(
        d.koRoundFormats.every(
          (f) => f == TournamentConfigDraft.defaultKoRoundFormat,
        ),
        isTrue,
      );
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
      // Two-axis defaults: group phase, single-out KO (no none), empty
      // per-round list (no koConfig set yet).
      expect(setup['vorrunde_type'], 'group_phase');
      expect(setup['ko_type'], 'single_out');
      expect(setup['ko_round_formats'], isEmpty);
    });

    test('club_id is null by default and round-trips when set', () {
      const none = TournamentConfigDraft();
      expect(none.toSetupConfig()['club_id'], isNull);

      const linked = TournamentConfigDraft(clubId: 'club-1');
      expect(linked.toSetupConfig()['club_id'], 'club-1');

      // copyWith carries it; clearClubId resets to a personal tournament.
      expect(none.copyWith(clubId: 'club-2').clubId, 'club-2');
      expect(linked.copyWith(clearClubId: true).clubId, isNull);
    });

    test('carries vorrunde/ko selection + ko_round_formats', () {
      const d = TournamentConfigDraft(
        vorrundeType: VorrundeType.schoch,
        koType: KoType.doubleOut,
        koRoundFormats: <MatchFormatSpec>[
          MatchFormatSpec(setsToWin: 2, maxSets: 3, timeLimitSeconds: 1800),
          MatchFormatSpec(
            setsToWin: 3,
            maxSets: 5,
            timeLimitSeconds: 3600,
            finalNoTiebreak: true,
          ),
        ],
      );
      final setup = d.toSetupConfig();
      expect(setup['vorrunde_type'], 'schoch');
      expect(setup['ko_type'], 'double_out');
      final rounds = setup['ko_round_formats']! as List<Object?>;
      expect(rounds, hasLength(2));
      expect(
        (rounds.last! as Map<String, Object?>)['final_no_tiebreak'],
        true,
      );
      expect((rounds.first! as Map<String, Object?>)['sets_to_win'], 2);
    });

    test('emits the Model-B consolation fields as snake_case (ADR-0028 §5)', () {
      const d = TournamentConfigDraft(
        koType: KoType.consolation,
        consolationMainBracketSize: 16,
        consolationDirectCount: 4,
        consolationName: 'Bâton Rouille',
      );
      final setup = d.toSetupConfig();
      expect(setup['consolation_main_bracket_size'], 16);
      expect(setup['consolation_direct_count'], 4);
      expect(setup['consolation_name'], 'Bâton Rouille');
    });

    test('Model-B defaults: size 8, direct count 0, null name', () {
      const d = TournamentConfigDraft();
      final setup = d.toSetupConfig();
      expect(setup['consolation_main_bracket_size'], 8);
      expect(setup['consolation_direct_count'], 0);
      expect(setup['consolation_name'], isNull);
    });

    test(
        'C11: an enabled consolation_bracket carries direct_count + '
        'main_bracket_size so the server actually consumes them', () {
      const d = TournamentConfigDraft(
        koType: KoType.consolation,
        consolationMainBracketSize: 16,
        consolationDirectCount: 4,
        consolationBracket: ConsolationConfig(enabled: true),
      );
      final setup = d.toSetupConfig();
      final cons = setup['consolation_bracket']! as Map<String, Object?>;
      expect(cons['enabled'], true);
      expect(cons['direct_count'], 4);
      expect(cons['main_bracket_size'], 16);
    });

    test(
        'C2/C11: main_bracket_size is only authoritative in consolation mode; '
        'omitted (null) for single-elimination', () {
      const d = TournamentConfigDraft(
        consolationMainBracketSize: 16,
        consolationBracket: ConsolationConfig(),
      );
      final setup = d.toSetupConfig();
      final cons = setup['consolation_bracket']! as Map<String, Object?>;
      expect(cons['main_bracket_size'], isNull);
    });

    test('serialises P6 fields into the snake_case wire shape', () {
      final d = TournamentConfigDraft(
        displayName: 'Bâton',
        // League categories only ship for a club-hosted tournament (C1 /
        // P6_SETUP_WIZARD_SPEC Screen 1); a club is required to assert them.
        clubId: 'club-1',
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
        // Use the non-default diggy=false here so the serialization is
        // exercised against a value that differs from the K05 default (true).
        ruleVariants: const RuleVariants(diggy: false),
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
        false,
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
        ruleVariants: RuleVariants(sureshot: true),
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

    test('serialises the team size range (min via param, max via setup)', () {
      const d = TournamentConfigDraft(teamSize: 2, maxTeamSize: 3);
      expect(d.toSetupConfig()['max_team_size'], 3);
    });

    test('validate flags a max team size below the minimum', () {
      const d = TournamentConfigDraft(
        displayName: 'Cup',
        teamSize: 3,
        maxTeamSize: 2,
      );
      final result = d.validate();
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.contains('Max. Spieler pro Team')),
        isTrue,
      );
    });
  });

  group('TournamentConfigDraft.fromDetail (P7 edit prefill)', () {
    // Builds a header whose wire `setup` / `matchFormatConfig` are the exact
    // serialization of [draft] — i.e. what tournament_get returns after
    // tournament_create persisted [draft]. fromDetail must invert it.
    TournamentDetailHeader headerFor(TournamentConfigDraft draft) {
      return TournamentDetailHeader(
        tournamentId: 't-1',
        displayName: draft.displayName ?? '',
        createdByUserId: 'u-1',
        clubId: null,
        teamSize: draft.teamSize,
        maxTeamSize: draft.maxTeamSize,
        minParticipants: draft.minParticipants,
        maxParticipants: draft.maxParticipants,
        format: draft.format,
        scoring: draft.scoring == 'classic'
            ? TournamentScoring.classic
            : TournamentScoring.ekc,
        matchFormatConfig: draft.toMatchFormatConfig(),
        tiebreakerOrder: draft.tiebreakerOrder,
        byePoints: null,
        forfeitPoints: null,
        status: TournamentStatus.published,
        publishedAt: null,
        startedAt: null,
        completedAt: null,
        setup: draft.toSetupConfig(),
      );
    }

    test('round-trips the prelim match format + meta fields', () {
      final original = TournamentConfigDraft(
        displayName: 'Sommer-Cup',
        // A club is required for league categories to round-trip (C1).
        clubId: 'club-1',
        minParticipants: 4,
        maxParticipants: 16,
        setsToWin: 3,
        maxSets: 5,
        roundTimeSeconds: 2400,
        prelimTiebreakAfterSeconds: 1500,
        location: 'Bern',
        venueAddress: 'Wankdorf',
        entryFeeCents: 1500,
        paymentMethods: const <String>['cash', 'twint'],
        leagueCategories: const <LeagueCategory>[LeagueCategory.a],
        scoring: 'classic',
        contactName: 'Lukas',
        eventStartsAt: DateTime.utc(2026, 7, 1, 9),
        registrationClosesAt: DateTime.utc(2026, 6, 28, 23),
      );

      final back = TournamentConfigDraft.fromDetail(headerFor(original));

      expect(back.displayName, 'Sommer-Cup');
      expect(back.minParticipants, 4);
      expect(back.maxParticipants, 16);
      expect(back.setsToWin, 3);
      expect(back.maxSets, 5);
      expect(back.roundTimeSeconds, 2400);
      expect(back.prelimTiebreakAfterSeconds, 1500);
      expect(back.location, 'Bern');
      expect(back.venueAddress, 'Wankdorf');
      expect(back.entryFeeCents, 1500);
      expect(back.paymentMethods, const <String>['cash', 'twint']);
      expect(back.leagueCategories, const <LeagueCategory>[LeagueCategory.a]);
      expect(back.scoring, 'classic');
      expect(back.contactName, 'Lukas');
      expect(back.eventStartsAt?.toUtc(), DateTime.utc(2026, 7, 1, 9));
      expect(
        back.registrationClosesAt?.toUtc(),
        DateTime.utc(2026, 6, 28, 23),
      );
    });

    test('preserves the organizing club id from the header', () {
      // Edit mode must keep the existing club so the organizer does not
      // accidentally detach the tournament when re-saving.
      final header = headerFor(const TournamentConfigDraft(displayName: 'Cup'));
      final withClub = TournamentDetailHeader(
        tournamentId: header.tournamentId,
        displayName: header.displayName,
        createdByUserId: header.createdByUserId,
        clubId: 'club-9',
        teamSize: header.teamSize,
        maxTeamSize: header.maxTeamSize,
        minParticipants: header.minParticipants,
        maxParticipants: header.maxParticipants,
        format: header.format,
        scoring: header.scoring,
        matchFormatConfig: header.matchFormatConfig,
        tiebreakerOrder: header.tiebreakerOrder,
        byePoints: header.byePoints,
        forfeitPoints: header.forfeitPoints,
        status: header.status,
        publishedAt: header.publishedAt,
        startedAt: header.startedAt,
        completedAt: header.completedAt,
        setup: header.setup,
      );

      expect(TournamentConfigDraft.fromDetail(withClub).clubId, 'club-9');
      expect(TournamentConfigDraft.fromDetail(header).clubId, isNull);
    });

    test('recovers the two-axis selection + bracket for a hybrid format', () {
      final ko = KoPhaseConfig(qualifierCount: 4, participantCount: 16);
      final original = TournamentConfigDraft(
        displayName: 'Hybrid-Cup',
        format: TournamentFormat.roundRobinThenKo,
        koType: KoType.doubleOut,
        bracketType: BracketType.doubleElimination,
        koConfig: ko,
        // diggy=false is the non-default value (K05 default is true), so the
        // round-trip is exercised against a value that differs from default.
        ruleVariants: const RuleVariants(sureshot: true, diggy: false),
      );

      final back = TournamentConfigDraft.fromDetail(headerFor(original));

      expect(back.format, TournamentFormat.roundRobinThenKo);
      expect(back.vorrundeType, VorrundeType.groupPhase);
      expect(back.koType, KoType.doubleOut);
      expect(back.bracketType, BracketType.doubleElimination);
      expect(back.koConfig?.qualifierCount, 4);
      expect(back.ruleVariants.sureshot, isTrue);
      expect(back.ruleVariants.diggy, isFalse);
    });

    test('round-trips the Model-B consolation fields (ADR-0028 §5)', () {
      final original = TournamentConfigDraft(
        displayName: 'Trost-Cup',
        format: TournamentFormat.roundRobinThenKo,
        koType: KoType.consolation,
        koConfig: KoPhaseConfig(qualifierCount: 8, participantCount: 16),
        consolationMainBracketSize: 16,
        consolationDirectCount: 4,
        consolationName: 'Bâton Rouille',
      );

      final back = TournamentConfigDraft.fromDetail(headerFor(original));

      expect(back.koType, KoType.consolation);
      expect(back.consolationMainBracketSize, 16);
      expect(back.consolationDirectCount, 4);
      expect(back.consolationName, 'Bâton Rouille');
    });

    test('falls back to defaults when the setup map is empty', () {
      const header = TournamentDetailHeader(
        tournamentId: 't-2',
        displayName: 'Bare',
        createdByUserId: 'u-1',
        clubId: null,
        teamSize: 1,
        maxTeamSize: 1,
        minParticipants: 2,
        maxParticipants: 8,
        format: TournamentFormat.roundRobin,
        scoring: TournamentScoring.ekc,
        matchFormatConfig: <String, Object?>{},
        tiebreakerOrder: <String>[],
        byePoints: null,
        forfeitPoints: null,
        status: TournamentStatus.draft,
        publishedAt: null,
        startedAt: null,
        completedAt: null,
      );

      final back = TournamentConfigDraft.fromDetail(header);

      expect(back.displayName, 'Bare');
      expect(back.vorrundeType, VorrundeType.groupPhase);
      // No "kein KO" axis value anymore: an empty setup defaults to single-out.
      expect(back.koType, KoType.singleOut);
      expect(back.scoring, 'ekc');
      expect(back.currency, 'CHF');
      expect(back.koConfig, isNull);
    });
  });
}
