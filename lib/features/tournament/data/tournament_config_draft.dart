import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:kubb_app/features/tournament/data/tournament_models.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Outcome of [TournamentConfigDraft.validate]. Mirrors the record-style
/// surface that `MatchConfigDraft.validate` exposes so the wizard can use
/// the same `isValid` / `issues` access pattern.
typedef TournamentConfigValidation = ({bool isValid, List<String> issues});

/// Returns null for a null/blank string, otherwise the trimmed value.
/// Keeps the setup payload free of empty-string columns.
String? _blankToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// Mutable wizard state for the tournament setup flow. The shape mirrors
/// the parameters of `TournamentRemote.createTournament` so the actions
/// provider can hand the draft straight to the RPC layer.
///
/// The flat `setsToWin` / `maxSets` / `roundTimeSeconds` / `basekubbsPerSide`
/// fields describe the PRELIM (group / Schoch) match format and feed
/// [toMatchFormatConfig]. The P6 setup fields (meta, league, rule
/// variants, [koMatchFormat], [pitchPlan], [mightyFinisherQuali],
/// [consolationBracket]) were added in Phase 0; the create-RPC wiring that
/// persists them lands with Screen 1.
@immutable
class TournamentConfigDraft {
  const TournamentConfigDraft({
    this.displayName,
    this.teamSize = 1,
    this.maxTeamSize = 1,
    this.minParticipants = 2,
    this.maxParticipants = 8,
    this.format = TournamentFormat.roundRobin,
    this.setsToWin = 2,
    this.maxSets = 3,
    this.roundTimeSeconds = 1800,
    this.basekubbsPerSide = 5,
    this.prelimTiebreakAfterSeconds,
    this.breakBetweenMatchesSeconds = 0,
    this.tiebreakerOrder = const <String>[
      'total_points',
      'buchholz_minus_h2h',
      'direct_comparison',
      'mighty_finisher_shootout',
    ],
    this.koConfig,
    this.bracketSeedingMode,
    this.leagueEligible = false,
    this.poolPhaseConfig,
    // --- P6 setup fields (Phase 0) ---
    this.location,
    this.venueAddress,
    this.eventStartsAt,
    this.checkinUntil,
    this.registrationClosesAt,
    this.weatherNote,
    this.infoFood,
    this.infoTravel,
    this.infoAccommodation,
    this.contactName,
    this.contactPhone,
    this.entryFeeCents,
    this.currency = 'CHF',
    this.paymentMethods = const <String>[],
    this.rulesPdfUrl,
    this.siteMapPdfUrl,
    this.leagueCategories = const <LeagueCategory>[],
    this.scoring = 'ekc',
    this.ruleVariants = const RuleVariants(),
    this.koMatchFormat,
    this.pitchPlan,
    this.mightyFinisherQuali,
    this.consolationBracket,
    this.bracketType = BracketType.singleElimination,
    this.koMatchup = KoMatchup.seedHighVsLow,
    this.koTiebreakMethod = KoTiebreakMethod.classicKingtossRemoval,
  });

  /// Visible name of the tournament. Null while the organizer hasn't
  /// typed anything yet; validate() flags both null and empty input.
  final String? displayName;

  /// Minimum players per team (1 = singles). The M1 `team_size` column.
  final int teamSize;

  /// Maximum players per team. Equals [teamSize] for a fixed-size team.
  final int maxTeamSize;

  final int minParticipants;
  final int maxParticipants;
  final TournamentFormat format;
  final int setsToWin;
  final int maxSets;
  final int roundTimeSeconds;
  final int basekubbsPerSide;

  /// Prelim tiebreak trigger in seconds; null = prelim played without a
  /// tiebreak (common in group phases). Must be < [roundTimeSeconds].
  final int? prelimTiebreakAfterSeconds;

  /// Configured break between prelim matches, in seconds.
  final int breakBetweenMatchesSeconds;

  final List<String> tiebreakerOrder;

  /// KO-phase configuration. Required when [format] is
  /// [TournamentFormat.singleElimination] or
  /// [TournamentFormat.roundRobinThenKo] (ADR-0017 §4).
  final KoPhaseConfig? koConfig;

  /// Seeding source for the KO bracket. Null until the wizard reaches
  /// the seeding step; defaults to [SeedingMode.auto] there.
  final SeedingMode? bracketSeedingMode;

  /// Mirrors `tournaments.league_eligible` (ADR-0017 §4). When `true`,
  /// [suggestedWithThirdPlacePlayoff] returns `true` so the wizard can
  /// pre-tick the bronze-match toggle.
  final bool leagueEligible;

  /// Pool-phase configuration. Null when the organizer leaves the pool
  /// toggle off (T9). Only meaningful for hybrid formats; the create-RPC
  /// ignores it for pure round-robin or single-elimination drafts.
  final PoolPhaseConfig? poolPhaseConfig;

  // --- P6 setup fields (Phase 0) ---------------------------------------

  /// Venue name / town.
  final String? location;

  /// Full venue address.
  final String? venueAddress;

  /// Official tournament start (date + time).
  final DateTime? eventStartsAt;

  /// On-site check-in deadline (Speakerpult), distinct from the in-app
  /// [registrationClosesAt] deadline.
  final DateTime? checkinUntil;

  /// In-app registration deadline.
  final DateTime? registrationClosesAt;

  final String? weatherNote;
  final String? infoFood;
  final String? infoTravel;
  final String? infoAccommodation;
  final String? contactName;
  final String? contactPhone;

  /// Participation fee in cents (e.g. CHF 10.- => 1000). Null = free.
  final int? entryFeeCents;
  final String currency;

  /// Allowed payment methods; subset of `{cash, twint, card}`.
  final List<String> paymentMethods;

  /// Supabase Storage object path/URL for the rules PDF.
  final String? rulesPdfUrl;

  /// Supabase Storage object path/URL for the site-map PDF.
  final String? siteMapPdfUrl;

  /// League tiers this tournament counts for (multi-select A/B/C).
  final List<LeagueCategory> leagueCategories;

  /// Scoring system: `ekc` (1 pt/basekubb + 3/set = 8) or `classic`.
  final String scoring;

  /// Rule toggles (sureshot / diggy / opening rule / penalty kubb).
  final RuleVariants ruleVariants;

  /// Separate KO-phase match format. Null => reuse the prelim format
  /// (flat fields). Decision: "Vorrunde + KO getrennt".
  final MatchFormatSpec? koMatchFormat;

  /// Pitch range/list this tournament occupies on a shared venue.
  final PitchPlan? pitchPlan;

  /// Mighty-Finisher shootout as a qualification stage (optional).
  final MightyFinisherQuali? mightyFinisherQuali;

  /// Consolation bracket ("Best of the Rest" / Bâton Rouille).
  final ConsolationConfig? consolationBracket;

  /// Single vs double elimination (P6_RULES_DECISIONS §D).
  final BracketType bracketType;

  /// Seeding/matchup pattern for the KO bracket (§C).
  final KoMatchup koMatchup;

  /// How a tied KO match is decided (§B).
  final KoTiebreakMethod koTiebreakMethod;

  static const int displayNameMinChars = 3;
  static const int displayNameMaxChars = 60;
  static const int participantsHardMin = 2;
  static const int participantsHardMax = 64;
  static const int setsToWinMin = 1;
  static const int setsToWinMax = 4;

  /// Payment-method vocabulary accepted by the schema CHECK constraint.
  static const List<String> paymentMethodVocabulary = <String>[
    'cash',
    'twint',
    'card',
  ];

  TournamentConfigDraft copyWith({
    String? displayName,
    int? teamSize,
    int? maxTeamSize,
    int? minParticipants,
    int? maxParticipants,
    TournamentFormat? format,
    int? setsToWin,
    int? maxSets,
    int? roundTimeSeconds,
    int? basekubbsPerSide,
    int? prelimTiebreakAfterSeconds,
    bool clearPrelimTiebreak = false,
    int? breakBetweenMatchesSeconds,
    List<String>? tiebreakerOrder,
    KoPhaseConfig? koConfig,
    SeedingMode? bracketSeedingMode,
    bool? leagueEligible,
    PoolPhaseConfig? poolPhaseConfig,
    bool clearPoolPhaseConfig = false,
    String? location,
    String? venueAddress,
    DateTime? eventStartsAt,
    DateTime? checkinUntil,
    DateTime? registrationClosesAt,
    String? weatherNote,
    String? infoFood,
    String? infoTravel,
    String? infoAccommodation,
    String? contactName,
    String? contactPhone,
    int? entryFeeCents,
    bool clearEntryFeeCents = false,
    String? currency,
    List<String>? paymentMethods,
    String? rulesPdfUrl,
    bool clearRulesPdfUrl = false,
    String? siteMapPdfUrl,
    bool clearSiteMapPdfUrl = false,
    List<LeagueCategory>? leagueCategories,
    String? scoring,
    RuleVariants? ruleVariants,
    MatchFormatSpec? koMatchFormat,
    bool clearKoMatchFormat = false,
    PitchPlan? pitchPlan,
    bool clearPitchPlan = false,
    MightyFinisherQuali? mightyFinisherQuali,
    bool clearMightyFinisherQuali = false,
    ConsolationConfig? consolationBracket,
    bool clearConsolationBracket = false,
    BracketType? bracketType,
    KoMatchup? koMatchup,
    KoTiebreakMethod? koTiebreakMethod,
  }) {
    return TournamentConfigDraft(
      displayName: displayName ?? this.displayName,
      teamSize: teamSize ?? this.teamSize,
      maxTeamSize: maxTeamSize ?? this.maxTeamSize,
      minParticipants: minParticipants ?? this.minParticipants,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      format: format ?? this.format,
      setsToWin: setsToWin ?? this.setsToWin,
      maxSets: maxSets ?? this.maxSets,
      roundTimeSeconds: roundTimeSeconds ?? this.roundTimeSeconds,
      basekubbsPerSide: basekubbsPerSide ?? this.basekubbsPerSide,
      prelimTiebreakAfterSeconds: clearPrelimTiebreak
          ? null
          : (prelimTiebreakAfterSeconds ?? this.prelimTiebreakAfterSeconds),
      breakBetweenMatchesSeconds:
          breakBetweenMatchesSeconds ?? this.breakBetweenMatchesSeconds,
      tiebreakerOrder: tiebreakerOrder ?? this.tiebreakerOrder,
      koConfig: koConfig ?? this.koConfig,
      bracketSeedingMode: bracketSeedingMode ?? this.bracketSeedingMode,
      leagueEligible: leagueEligible ?? this.leagueEligible,
      poolPhaseConfig: clearPoolPhaseConfig
          ? null
          : (poolPhaseConfig ?? this.poolPhaseConfig),
      location: location ?? this.location,
      venueAddress: venueAddress ?? this.venueAddress,
      eventStartsAt: eventStartsAt ?? this.eventStartsAt,
      checkinUntil: checkinUntil ?? this.checkinUntil,
      registrationClosesAt: registrationClosesAt ?? this.registrationClosesAt,
      weatherNote: weatherNote ?? this.weatherNote,
      infoFood: infoFood ?? this.infoFood,
      infoTravel: infoTravel ?? this.infoTravel,
      infoAccommodation: infoAccommodation ?? this.infoAccommodation,
      contactName: contactName ?? this.contactName,
      contactPhone: contactPhone ?? this.contactPhone,
      entryFeeCents:
          clearEntryFeeCents ? null : (entryFeeCents ?? this.entryFeeCents),
      currency: currency ?? this.currency,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      rulesPdfUrl:
          clearRulesPdfUrl ? null : (rulesPdfUrl ?? this.rulesPdfUrl),
      siteMapPdfUrl:
          clearSiteMapPdfUrl ? null : (siteMapPdfUrl ?? this.siteMapPdfUrl),
      leagueCategories: leagueCategories ?? this.leagueCategories,
      scoring: scoring ?? this.scoring,
      ruleVariants: ruleVariants ?? this.ruleVariants,
      koMatchFormat:
          clearKoMatchFormat ? null : (koMatchFormat ?? this.koMatchFormat),
      pitchPlan: clearPitchPlan ? null : (pitchPlan ?? this.pitchPlan),
      mightyFinisherQuali: clearMightyFinisherQuali
          ? null
          : (mightyFinisherQuali ?? this.mightyFinisherQuali),
      consolationBracket: clearConsolationBracket
          ? null
          : (consolationBracket ?? this.consolationBracket),
      bracketType: bracketType ?? this.bracketType,
      koMatchup: koMatchup ?? this.koMatchup,
      koTiebreakMethod: koTiebreakMethod ?? this.koTiebreakMethod,
    );
  }

  /// Whether the wizard should surface the pool-phase configuration step.
  /// Pool grouping is only meaningful for hybrid formats that follow a
  /// round-robin / Schoch / Swiss stage with a KO bracket.
  bool get supportsPoolPhase =>
      format == TournamentFormat.roundRobinThenKo ||
      format == TournamentFormat.schochThenKo ||
      format == TournamentFormat.swissThenKo;

  /// Whether a KO phase has to be configured for the selected [format].
  /// Covers the pure single-elimination format plus every hybrid
  /// (group/Schoch/Swiss → KO) variant.
  bool get requiresKoConfig =>
      format == TournamentFormat.singleElimination ||
      format == TournamentFormat.roundRobinThenKo ||
      format == TournamentFormat.schochThenKo ||
      format == TournamentFormat.swissThenKo;

  /// Wizard pre-fill value for the `withThirdPlacePlayoff` toggle
  /// (ADR-0017 §4). The wizard may still let the organizer override it.
  bool get suggestedWithThirdPlacePlayoff => leagueEligible;

  TournamentConfigValidation validate() {
    final issues = <String>[];
    final name = displayName?.trim() ?? '';
    if (name.isEmpty) {
      issues.add('Turniername fehlt.');
    } else if (name.length < displayNameMinChars) {
      issues.add('Turniername muss mindestens $displayNameMinChars Zeichen haben.');
    } else if (name.length > displayNameMaxChars) {
      issues.add('Turniername darf höchstens $displayNameMaxChars Zeichen haben.');
    }

    if (teamSize < 1 || teamSize > 6) {
      issues.add('Min. Spieler pro Team muss zwischen 1 und 6 liegen.');
    }
    if (maxTeamSize < teamSize || maxTeamSize > 6) {
      issues.add('Max. Spieler pro Team darf nicht kleiner als Min. sein.');
    }

    if (minParticipants < participantsHardMin) {
      issues.add('Mindestens $participantsHardMin Teilnehmer.');
    }
    if (maxParticipants > participantsHardMax) {
      issues.add('Höchstens $participantsHardMax Teilnehmer.');
    }
    if (minParticipants > maxParticipants) {
      issues.add('Min. Teilnehmer darf nicht grösser als Max. sein.');
    }

    if (setsToWin < setsToWinMin || setsToWin > setsToWinMax) {
      issues.add('Sätze zum Sieg muss zwischen $setsToWinMin und $setsToWinMax liegen.');
    }
    final requiredMaxSets = 2 * setsToWin - 1;
    if (maxSets < requiredMaxSets) {
      issues.add('Max. Sätze muss mindestens $requiredMaxSets sein.');
    }

    if (roundTimeSeconds < 60) {
      issues.add('Rundenzeit muss mindestens eine Minute sein.');
    }

    final tbAfter = prelimTiebreakAfterSeconds;
    if (tbAfter != null && (tbAfter < 60 || tbAfter > roundTimeSeconds)) {
      issues.add(
          'Tiebreak-Zeit muss zwischen 1 Minute und dem Zeitlimit liegen.');
    }
    if (breakBetweenMatchesSeconds < 0) {
      issues.add('Pause zwischen Matches darf nicht negativ sein.');
    }

    if (basekubbsPerSide < 1) {
      issues.add('Basiskubbs pro Seite muss mindestens 1 sein.');
    }

    if (requiresKoConfig && koConfig == null) {
      issues.add('KO-Phase-Konfiguration fehlt.');
    }

    // --- P6 setup fields ---
    if (scoring != 'ekc' && scoring != 'classic') {
      issues.add('Wertung muss EKC oder klassisch sein.');
    }
    final fee = entryFeeCents;
    if (fee != null && fee < 0) {
      issues.add('Teilnahmegebühr darf nicht negativ sein.');
    }
    for (final method in paymentMethods) {
      if (!paymentMethodVocabulary.contains(method)) {
        issues.add('Unbekannte Zahlungsart: $method.');
      }
    }
    if (leagueCategories.toSet().length != leagueCategories.length) {
      issues.add('Liga-Kategorien dürfen sich nicht wiederholen.');
    }
    final closes = registrationClosesAt;
    final starts = eventStartsAt;
    if (closes != null && starts != null && closes.isAfter(starts)) {
      issues.add('Anmeldeschluss muss vor dem Turnierstart liegen.');
    }
    issues
      ..addAll(koMatchFormat?.issues() ?? const <String>[])
      ..addAll(pitchPlan?.issues() ?? const <String>[])
      ..addAll(mightyFinisherQuali?.issues() ?? const <String>[])
      ..addAll(consolationBracket?.issues() ?? const <String>[]);

    return (isValid: issues.isEmpty, issues: issues);
  }

  /// Shape consumed by the `tournament_create` RPC's
  /// `p_match_format_config` parameter (the PRELIM / group format). Kept
  /// as a plain map so the wire contract can evolve without a Dart
  /// migration.
  Map<String, Object?> toMatchFormatConfig() {
    return <String, Object?>{
      'sets_to_win': setsToWin,
      'max_sets': maxSets,
      'round_time_seconds': roundTimeSeconds,
      'basekubbs_per_side': basekubbsPerSide,
      'tiebreak_enabled': prelimTiebreakAfterSeconds != null,
      'tiebreak_after_seconds': prelimTiebreakAfterSeconds,
      'break_between_matches_seconds': breakBetweenMatchesSeconds,
    };
  }

  /// Shape consumed by the `tournament_create` RPC's `p_setup` parameter
  /// (the P6 setup fields). Keys match the snake_case column / JSONB
  /// shape on the SQL side; nested value objects round-trip through their
  /// own `toJson`. DateTimes are emitted as UTC ISO-8601 strings that the
  /// RPC casts to `timestamptz`.
  Map<String, Object?> toSetupConfig() {
    return <String, Object?>{
      'location': _blankToNull(location),
      'venue_address': _blankToNull(venueAddress),
      'event_starts_at': eventStartsAt?.toUtc().toIso8601String(),
      'checkin_until': checkinUntil?.toUtc().toIso8601String(),
      'registration_closes_at':
          registrationClosesAt?.toUtc().toIso8601String(),
      'weather_note': _blankToNull(weatherNote),
      'info_food': _blankToNull(infoFood),
      'info_travel': _blankToNull(infoTravel),
      'info_accommodation': _blankToNull(infoAccommodation),
      'contact_name': _blankToNull(contactName),
      'contact_phone': _blankToNull(contactPhone),
      'entry_fee_cents': entryFeeCents,
      'currency': currency,
      'max_team_size': maxTeamSize,
      'payment_methods': paymentMethods,
      'league_categories': <String>[
        for (final c in leagueCategories) c.wire,
      ],
      'scoring': scoring,
      'rule_variants': ruleVariants.toJson(),
      'ko_match_format': koMatchFormat?.toJson(),
      'pitch_plan': pitchPlan?.toJson(),
      'mighty_finisher_quali': mightyFinisherQuali?.toJson(),
      'consolation_bracket': consolationBracket?.toJson(),
      'pool_phase_config': poolPhaseConfig?.toWire(),
      'ko_config': koConfig?.toWire(),
      'bracket_type': bracketType.wire,
      'ko_matchup': koMatchup.wire,
      'ko_tiebreak_method': koTiebreakMethod.wire,
      'rules_pdf_url': rulesPdfUrl,
      'site_map_pdf_url': siteMapPdfUrl,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentConfigDraft &&
          other.displayName == displayName &&
          other.teamSize == teamSize &&
          other.maxTeamSize == maxTeamSize &&
          other.minParticipants == minParticipants &&
          other.maxParticipants == maxParticipants &&
          other.format == format &&
          other.setsToWin == setsToWin &&
          other.maxSets == maxSets &&
          other.roundTimeSeconds == roundTimeSeconds &&
          other.basekubbsPerSide == basekubbsPerSide &&
          other.prelimTiebreakAfterSeconds == prelimTiebreakAfterSeconds &&
          other.breakBetweenMatchesSeconds == breakBetweenMatchesSeconds &&
          listEquals(other.tiebreakerOrder, tiebreakerOrder) &&
          other.koConfig == koConfig &&
          other.bracketSeedingMode == bracketSeedingMode &&
          other.leagueEligible == leagueEligible &&
          other.poolPhaseConfig == poolPhaseConfig &&
          other.location == location &&
          other.venueAddress == venueAddress &&
          other.eventStartsAt == eventStartsAt &&
          other.checkinUntil == checkinUntil &&
          other.registrationClosesAt == registrationClosesAt &&
          other.weatherNote == weatherNote &&
          other.infoFood == infoFood &&
          other.infoTravel == infoTravel &&
          other.infoAccommodation == infoAccommodation &&
          other.contactName == contactName &&
          other.contactPhone == contactPhone &&
          other.entryFeeCents == entryFeeCents &&
          other.currency == currency &&
          listEquals(other.paymentMethods, paymentMethods) &&
          other.rulesPdfUrl == rulesPdfUrl &&
          other.siteMapPdfUrl == siteMapPdfUrl &&
          listEquals(other.leagueCategories, leagueCategories) &&
          other.scoring == scoring &&
          other.ruleVariants == ruleVariants &&
          other.koMatchFormat == koMatchFormat &&
          other.pitchPlan == pitchPlan &&
          other.mightyFinisherQuali == mightyFinisherQuali &&
          other.consolationBracket == consolationBracket &&
          other.bracketType == bracketType &&
          other.koMatchup == koMatchup &&
          other.koTiebreakMethod == koTiebreakMethod;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        displayName,
        teamSize,
        maxTeamSize,
        minParticipants,
        maxParticipants,
        format,
        setsToWin,
        maxSets,
        roundTimeSeconds,
        basekubbsPerSide,
        prelimTiebreakAfterSeconds,
        breakBetweenMatchesSeconds,
        Object.hashAll(tiebreakerOrder),
        koConfig,
        bracketSeedingMode,
        leagueEligible,
        poolPhaseConfig,
        location,
        venueAddress,
        eventStartsAt,
        checkinUntil,
        registrationClosesAt,
        weatherNote,
        infoFood,
        infoTravel,
        infoAccommodation,
        contactName,
        contactPhone,
        entryFeeCents,
        currency,
        Object.hashAll(paymentMethods),
        rulesPdfUrl,
        siteMapPdfUrl,
        Object.hashAll(leagueCategories),
        scoring,
        ruleVariants,
        koMatchFormat,
        pitchPlan,
        mightyFinisherQuali,
        consolationBracket,
        bracketType,
        koMatchup,
        koTiebreakMethod,
      ]);
}
