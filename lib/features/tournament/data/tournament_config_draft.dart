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
    this.clubId,
    this.clubChoiceMade = false,
    this.teamSize = 1,
    this.maxTeamSize = 1,
    this.minParticipants = 2,
    this.maxParticipants = 8,
    this.format = TournamentFormat.roundRobin,
    this.setsToWin = 2,
    // K14: prelim "Max. Sätze" defaults to 2. Draws are allowed in the prelim
    // (maxSets is decoupled from setsToWin, so even values are valid).
    this.maxSets = 2,
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
    this.vorrundeType = VorrundeType.groupPhase,
    this.koType = KoType.singleOut,
    this.koRoundFormats = const <MatchFormatSpec>[],
    // --- Model-B (consolation / Trostturnier) config (ADR-0028 §5) ---
    this.consolationMainBracketSize = 8,
    this.consolationDirectCount = 0,
    this.consolationName,
  });

  /// Rebuilds a draft from a [TournamentDetailHeader] so the setup wizard
  /// can open in EDIT mode pre-filled with the tournament's current values
  /// (P7 edit-after-publish). Inverts [toMatchFormatConfig] (prelim format,
  /// read from [TournamentDetailHeader.matchFormatConfig]) and
  /// [toSetupConfig] (P6 fields, read from the opaque
  /// [TournamentDetailHeader.setup] wire map). The two-axis selection
  /// ([vorrundeType] / [koType]) is recovered from the wire keys when
  /// present, falling back to deriving it from the legacy [format] +
  /// [bracketType] so older rows without the explicit axes still prefill.
  /// Keys missing from the wire map leave the corresponding field on its
  /// constructor default.
  factory TournamentConfigDraft.fromDetail(TournamentDetailHeader header) {
    final cfg = header.matchFormatConfig;
    final setup = header.setup;

    int? intOf(Object? v) =>
        v == null ? null : (v is int ? v : (v as num).toInt());
    DateTime? dateOf(Object? v) =>
        v == null ? null : DateTime.parse(v as String).toLocal();
    Map<String, Object?>? mapOf(Object? v) =>
        v is Map ? v.cast<String, Object?>() : null;
    List<String> stringList(Object? v) => v is List
        ? v.map((e) => e.toString()).toList(growable: false)
        : const <String>[];

    // ---- Prelim match format (inverts toMatchFormatConfig) ----
    final tbAfter = intOf(cfg['tiebreak_after_seconds']);
    final tbEnabled = cfg['tiebreak_enabled'] == true;

    // ---- Two-axis selection ----
    final vorrundeWire = setup['vorrunde_type'] as String?;
    final koWire = setup['ko_type'] as String?;
    final format = header.format;
    final bracketType = setup['bracket_type'] is String
        ? BracketType.fromWire(setup['bracket_type']! as String)
        : BracketType.singleElimination;
    final vorrundeType = vorrundeWire != null
        ? VorrundeType.fromWire(vorrundeWire)
        : _vorrundeFromFormat(format);
    final koType = koWire != null
        ? KoType.fromWire(koWire)
        : _koFromFormat(format, bracketType);

    // ---- Nested value objects ----
    final ruleVariantsJson = mapOf(setup['rule_variants']);
    final koMatchFormatJson = mapOf(setup['ko_match_format']);
    final pitchPlanJson = mapOf(setup['pitch_plan']);
    final mightyJson = mapOf(setup['mighty_finisher_quali']);
    final consolationJson = mapOf(setup['consolation_bracket']);
    final koConfigJson = mapOf(setup['ko_config']);
    final poolConfigJson = mapOf(setup['pool_phase_config']);
    final koRoundFormatsRaw = setup['ko_round_formats'];

    final maxTeamSize = intOf(setup['max_team_size']) ?? header.maxTeamSize;

    return TournamentConfigDraft(
      displayName: header.displayName,
      clubId: header.clubId,
      // EDIT mode: the club choice was already made when the tournament was
      // created, so the Stammdaten step is valid without re-picking (K03).
      clubChoiceMade: true,
      teamSize: header.teamSize,
      maxTeamSize: maxTeamSize < header.teamSize ? header.teamSize : maxTeamSize,
      minParticipants: header.minParticipants,
      maxParticipants: header.maxParticipants,
      format: format,
      setsToWin: intOf(cfg['sets_to_win']) ?? 2,
      // K14: fall back to the 2-default when the stored config lacks max_sets,
      // consistent with the constructor default.
      maxSets: intOf(cfg['max_sets']) ?? 2,
      roundTimeSeconds: intOf(cfg['round_time_seconds']) ?? 1800,
      basekubbsPerSide: intOf(cfg['basekubbs_per_side']) ?? 5,
      prelimTiebreakAfterSeconds: tbEnabled ? tbAfter : null,
      breakBetweenMatchesSeconds:
          intOf(cfg['break_between_matches_seconds']) ?? 0,
      tiebreakerOrder: header.tiebreakerOrder.isEmpty
          ? const <String>[
              'total_points',
              'buchholz_minus_h2h',
              'direct_comparison',
              'mighty_finisher_shootout',
            ]
          : header.tiebreakerOrder,
      koConfig: koConfigJson == null ? null : _koConfigFromWire(koConfigJson),
      poolPhaseConfig:
          poolConfigJson == null ? null : _poolConfigFromWire(poolConfigJson),
      location: setup['location'] as String?,
      venueAddress: setup['venue_address'] as String?,
      eventStartsAt: dateOf(setup['event_starts_at']),
      checkinUntil: dateOf(setup['checkin_until']),
      registrationClosesAt: dateOf(setup['registration_closes_at']),
      weatherNote: setup['weather_note'] as String?,
      infoFood: setup['info_food'] as String?,
      infoTravel: setup['info_travel'] as String?,
      infoAccommodation: setup['info_accommodation'] as String?,
      contactName: setup['contact_name'] as String?,
      contactPhone: setup['contact_phone'] as String?,
      entryFeeCents: intOf(setup['entry_fee_cents']),
      currency: setup['currency'] as String? ?? 'CHF',
      paymentMethods: stringList(setup['payment_methods']),
      rulesPdfUrl: setup['rules_pdf_url'] as String?,
      siteMapPdfUrl: setup['site_map_pdf_url'] as String?,
      leagueCategories: <LeagueCategory>[
        for (final c in stringList(setup['league_categories']))
          LeagueCategory.fromWire(c),
      ],
      scoring: setup['scoring'] as String? ?? header.scoring.name,
      ruleVariants: ruleVariantsJson == null
          ? const RuleVariants()
          : RuleVariants.fromJson(ruleVariantsJson),
      koMatchFormat: koMatchFormatJson == null
          ? null
          : MatchFormatSpec.fromJson(koMatchFormatJson),
      pitchPlan:
          pitchPlanJson == null ? null : PitchPlan.fromJson(pitchPlanJson),
      mightyFinisherQuali: mightyJson == null
          ? null
          : MightyFinisherQuali.fromJson(mightyJson),
      consolationBracket: consolationJson == null
          ? null
          : ConsolationConfig.fromJson(consolationJson),
      bracketType: bracketType,
      koMatchup: setup['ko_matchup'] is String
          ? KoMatchup.fromWire(setup['ko_matchup']! as String)
          : KoMatchup.seedHighVsLow,
      koTiebreakMethod: setup['ko_tiebreak_method'] is String
          ? KoTiebreakMethod.fromWire(setup['ko_tiebreak_method']! as String)
          : KoTiebreakMethod.classicKingtossRemoval,
      vorrundeType: vorrundeType,
      koType: koType,
      koRoundFormats: koRoundFormatsRaw is List
          ? <MatchFormatSpec>[
              for (final f in koRoundFormatsRaw)
                MatchFormatSpec.fromJson((f as Map).cast<String, Object?>()),
            ]
          : const <MatchFormatSpec>[],
      consolationMainBracketSize:
          intOf(setup['consolation_main_bracket_size']) ?? 8,
      consolationDirectCount: intOf(setup['consolation_direct_count']) ?? 0,
      // K17: the name is persisted INSIDE consolation_bracket.name (the
      // standalone consolation_name key is dropped by the create RPC). Prefer
      // the nested value; fall back to the legacy top-level key for older rows.
      consolationName: (consolationJson?['name'] as String?) ??
          setup['consolation_name'] as String?,
    );
  }

  /// Maps the legacy [TournamentFormat] back to the prelim axis (inverse
  /// of [formatFor]). Used by `fromDetail` when the explicit
  /// `vorrunde_type` wire key is absent.
  static VorrundeType _vorrundeFromFormat(TournamentFormat format) =>
      switch (format) {
        TournamentFormat.roundRobin ||
        TournamentFormat.singleElimination ||
        TournamentFormat.roundRobinThenKo =>
          VorrundeType.groupPhase,
        TournamentFormat.schoch ||
        TournamentFormat.swiss ||
        TournamentFormat.schochThenKo ||
        TournamentFormat.swissThenKo =>
          VorrundeType.schoch,
      };

  /// Maps the legacy [TournamentFormat] (+ bracket type for the
  /// single/double distinction) back to the KO axis. Used by `fromDetail`
  /// when the explicit `ko_type` wire key is absent. Every tournament has a
  /// KO stage now, so the default is [KoType.singleOut]; a stored
  /// consolation config is recovered from the explicit `ko_type` wire key
  /// (handled in `fromDetail`), not from the legacy format.
  static KoType _koFromFormat(TournamentFormat format, BracketType bracket) {
    return bracket == BracketType.doubleElimination
        ? KoType.doubleOut
        : KoType.singleOut;
  }

  /// Inverts `KoPhaseConfigWire.toWire`. The participant count is not
  /// available on the stored wire shape, so the stored qualifier count
  /// doubles as the participant-count floor; the validator only requires
  /// `2 <= qualifier <= participant`.
  static KoPhaseConfig _koConfigFromWire(Map<String, Object?> json) {
    final qualifier = (json['qualifier_count'] as num?)?.toInt() ?? 2;
    return KoPhaseConfig(
      qualifierCount: qualifier,
      participantCount: qualifier,
      withThirdPlacePlayoff: json['with_third_place_playoff'] as bool? ?? false,
      seedingMode: json['seeding_mode'] == 'manual'
          ? SeedingMode.manual
          : SeedingMode.auto,
    );
  }

  /// Inverts `PoolPhaseConfigWire.toWire`.
  static PoolPhaseConfig _poolConfigFromWire(Map<String, Object?> json) {
    return PoolPhaseConfig(
      groupCount: (json['group_count'] as num?)?.toInt() ?? 1,
      qualifiersPerGroup: (json['qualifiers_per_group'] as num?)?.toInt() ?? 1,
      strategy: PoolGroupingStrategy.values.firstWhere(
        (s) => s.name == json['strategy'],
        orElse: () => PoolGroupingStrategy.snake,
      ),
      randomSeed: (json['random_seed'] as num?)?.toInt(),
    );
  }

  /// Default seed for a per-KO-round format when neither [koMatchFormat]
  /// nor an existing entry is available. Mirrors the flat prelim defaults.
  static const MatchFormatSpec defaultKoRoundFormat = MatchFormatSpec(
    setsToWin: 2,
    maxSets: 3,
    timeLimitSeconds: 1800,
    tiebreakEnabled: false,
  );

  /// Deterministic per-round default ruleset per P6_RULES_DECISIONS §A,
  /// counted from the back ([totalRounds] = number of KO rounds, [roundIndex]
  /// 0-based with 0 = first round … `totalRounds - 1` = final):
  ///   * final (last round)           → Bo5, 60 min, no tiebreak, finalNoTiebreak
  ///   * semifinal (R-1)              → Bo5, 60 min, no tiebreak
  ///   * quarter/eighth (R-3 .. R-2)  → Bo5, 60 min, tiebreak after 40 min
  ///   * earlier rounds (< R-3)       → Bo3, 40 min, tiebreak after 25 min
  /// Used to seed new entries in [withResizedKoRoundFormats].
  static MatchFormatSpec defaultKoRoundFormatFor(
    int roundIndex,
    int totalRounds,
  ) {
    // Rounds remaining until (and including) the final; final == 1.
    final fromBack = totalRounds - roundIndex;
    if (fromBack <= 1) {
      // Final.
      return const MatchFormatSpec(
        setsToWin: 3,
        maxSets: 5,
        timeLimitSeconds: 3600,
        tiebreakEnabled: false,
        finalNoTiebreak: true,
      );
    }
    if (fromBack == 2) {
      // Semifinal.
      return const MatchFormatSpec(
        setsToWin: 3,
        maxSets: 5,
        timeLimitSeconds: 3600,
        tiebreakEnabled: false,
      );
    }
    if (fromBack <= 4) {
      // Quarter / eighth: Bo5 with a 40-minute tiebreak.
      return const MatchFormatSpec(
        setsToWin: 3,
        maxSets: 5,
        timeLimitSeconds: 3600,
        tiebreakAfterSeconds: 2400,
      );
    }
    // Earlier rounds: Bo3 with a 25-minute tiebreak.
    return const MatchFormatSpec(
      setsToWin: 2,
      maxSets: 3,
      timeLimitSeconds: 2400,
      tiebreakAfterSeconds: 1500,
    );
  }

  // ---- Two-axis format selection (Vorrunde × KO) ----------------------

  /// Preliminary stage type (group phase vs Schoch). Together with
  /// [koType] this is the user-facing format choice; [derivedFormat] and
  /// [derivedBracketType] translate the pair to the legacy enum + bracket
  /// the RPC/server still consume. The controller keeps [format] and
  /// [bracketType] in sync with these axes.
  final VorrundeType vorrundeType;

  /// KO stage type (single-out / double-out / consolation), the second
  /// format axis. See [vorrundeType].
  final KoType koType;

  // --- Model-B (consolation / Trostturnier) config (ADR-0028 §5) -------
  // Only meaningful when [koType] is [KoType.consolation]; the engine
  // (Block E) consumes these — here they are draft state + persistence
  // only, emitted as snake_case in [toSetupConfig].

  /// Consolation main-bracket size (power of two). Mirrors the KO bracket
  /// size for the consolation model. Wire key `consolation_main_bracket_size`.
  final int consolationMainBracketSize;

  /// Number of prelim teams that start directly in the consolation bracket
  /// (free integer >= 0, default 0). Wire key `consolation_direct_count`.
  final int consolationDirectCount;

  /// Free display name of the consolation/Trostturnier. Null = default name.
  /// Wire key `consolation_name`.
  final String? consolationName;

  /// Per-KO-round match rulesets, index 0 = first KO round … last = final.
  /// Length is derived from the KO bracket size via
  /// [koRoundCountFor]; [withResizedKoRoundFormats] keeps it in step with
  /// the qualifier count. Empty when no KO phase is configured. The flat
  /// prelim ruleset stays separate; the single [koMatchFormat] seeds the
  /// per-round list as a fallback default.
  final List<MatchFormatSpec> koRoundFormats;

  /// Visible name of the tournament. Null while the organizer hasn't
  /// typed anything yet; validate() flags both null and empty input.
  final String? displayName;

  /// Optional organizing club id (`tournaments.club_id`). Null = personal
  /// tournament with no club; then only the creator may manage it. When
  /// set, owner/admin/organizer members of that club may also manage it.
  /// Mirrors the per-tournament authority decision; round-trips through
  /// the `club_id` setup key.
  final String? clubId;

  /// K03: whether the organizer has actively made the club choice in the
  /// wizard — either picking a club ([clubId] != null) OR explicitly
  /// choosing "Spasstournier – ohne Wertung" ([clubId] == null). A bare
  /// default draft has `false` here so the wizard can tell "not chosen yet"
  /// apart from "explicitly no club" (the dropdown alone can't, since both
  /// map to a null `clubId`). Not persisted on the wire — the server only
  /// needs the resulting [clubId]; this is wizard-validation state.
  final bool clubChoiceMade;

  /// K02: a tournament is rating-/league-relevant only when an organizing
  /// club is selected. "Spasstournier – ohne Wertung" ([clubId] == null) is
  /// never rated — the points/league system must skip it. Derived from
  /// [clubId] so no separate persisted flag is required; the wertungsfrei
  /// state round-trips implicitly via the `club_id` setup key (and
  /// [toSetupConfig] emits an empty `league_categories` for it).
  bool get isRated => clubId != null;

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

  /// K01: max length of the user-typed name. The auto-appended 4-digit year
  /// suffix (` 2026`, +5 chars) is added on top and is exempt from this
  /// limit, so [resolvedDisplayName] may exceed it by the suffix length.
  static const int displayNameMaxChars = 60;

  /// K01: the tournament name with the relevant year appended for
  /// uniqueness across years (e.g. "Sommercup" → "Sommercup 2026"), so a
  /// host re-running the same tournament next year stays distinguishable.
  ///
  /// Idempotent: if the trimmed name already contains a 4-digit year
  /// (1900–2099) it is returned unchanged. The appended year is
  /// [eventStartsAt].year when the start date is set, otherwise the current
  /// year ([DateTime.now]). Returns null when no name is set yet.
  String? get resolvedDisplayName {
    final name = displayName?.trim();
    if (name == null || name.isEmpty) return name;
    if (_containsFourDigitYear(name)) return name;
    final year = eventStartsAt?.year ?? DateTime.now().year;
    return '$name $year';
  }

  /// True when [text] already contains a standalone 4-digit year in the
  /// 1900–2099 range, so [resolvedDisplayName] does not append a second one.
  static bool _containsFourDigitYear(String text) =>
      RegExp(r'(?<!\d)(19|20)\d{2}(?!\d)').hasMatch(text);

  // K09: no user-facing minimum participant count anymore. We keep a non-zero
  // floor (the KO minimum) purely as an internal sanity bound; it is never
  // shown in the UI nor user-validated.
  static const int participantsHardMin = 1;
  // K10: tournaments must be configurable with up to 1000 participants.
  static const int participantsHardMax = 1000;
  // K11: the KO bracket size is decoupled from the participant count. A bracket
  // is a power of two; we cap it at 64 (a 6-round main bracket) which is a sane
  // ceiling for a live Kubb event regardless of how many players register.
  static const int koBracketSizeCap = 64;
  static const int setsToWinMin = 1;
  static const int setsToWinMax = 4;

  /// Prelim "Max. Sätze" bounds. Decoupled from [setsToWin] (P6 spec:
  /// prelim needs no unique per-match winner, so even values like 2 — a
  /// possible draw — are allowed).
  static const int maxSetsMin = 1;
  static const int maxSetsMax = 9;

  /// Payment-method vocabulary accepted by the schema CHECK constraint.
  static const List<String> paymentMethodVocabulary = <String>[
    'cash',
    'twint',
    'card',
  ];

  TournamentConfigDraft copyWith({
    String? displayName,
    String? clubId,
    bool clearClubId = false,
    bool? clubChoiceMade,
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
    VorrundeType? vorrundeType,
    KoType? koType,
    List<MatchFormatSpec>? koRoundFormats,
    int? consolationMainBracketSize,
    int? consolationDirectCount,
    String? consolationName,
    bool clearConsolationName = false,
  }) {
    return TournamentConfigDraft(
      displayName: displayName ?? this.displayName,
      clubId: clearClubId ? null : (clubId ?? this.clubId),
      clubChoiceMade: clubChoiceMade ?? this.clubChoiceMade,
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
      vorrundeType: vorrundeType ?? this.vorrundeType,
      koType: koType ?? this.koType,
      koRoundFormats: koRoundFormats ?? this.koRoundFormats,
      consolationMainBracketSize:
          consolationMainBracketSize ?? this.consolationMainBracketSize,
      consolationDirectCount:
          consolationDirectCount ?? this.consolationDirectCount,
      consolationName: clearConsolationName
          ? null
          : (consolationName ?? this.consolationName),
    );
  }

  // ---- Two-axis ⇄ legacy enum mapping ---------------------------------

  /// Derives the legacy [TournamentFormat] from the ([vorrundeType],
  /// [koType]) pair so the RPC/server keep working unchanged. Every
  /// tournament has a KO stage, so a prelim always maps to its hybrid
  /// (…ThenKo) format:
  ///   groupPhase + any KO → roundRobinThenKo
  ///   schoch     + any KO → swissThenKo   (server routes swiss == schoch)
  static TournamentFormat formatFor(VorrundeType vorrunde, KoType ko) {
    return switch (vorrunde) {
      VorrundeType.groupPhase => TournamentFormat.roundRobinThenKo,
      VorrundeType.schoch => TournamentFormat.swissThenKo,
    };
  }

  /// Derives the [BracketType] from a [KoType]. Double-Elimination maps to
  /// [BracketType.doubleElimination] (ADR-0027); Single-Out and the
  /// consolation/Trostturnier model both use a single-elimination main
  /// bracket (ADR-0028 — the consolation bracket is an additive second tree
  /// layered on `ConsolationConfig`, not a different main bracket type).
  static BracketType bracketTypeFor(KoType ko) => switch (ko) {
        KoType.doubleOut => BracketType.doubleElimination,
        KoType.singleOut || KoType.consolation =>
          BracketType.singleElimination,
      };

  /// Number of KO rounds for a given qualifier count: `ceil(log2(n))`
  /// (e.g. 8 → 3, 6 → 3, 4 → 2, 2 → 1). Returns 0 for < 2 qualifiers.
  static int koRoundCountFor(int qualifierCount) {
    if (qualifierCount < 2) return 0;
    var rounds = 0;
    var capacity = 1;
    while (capacity < qualifierCount) {
      capacity *= 2;
      rounds++;
    }
    return rounds;
  }

  /// Default single-pool [PoolPhaseConfig] for the Schoch Vorrunde.
  ///
  /// User requirement (P5/P6): selecting "Schoch" must automatically produce
  /// EXACTLY ONE pool that holds ALL participants — i.e. `group_count == 1` —
  /// so the hybrid (`swiss_then_ko`) format always carries a valid
  /// `pool_phase_config` and `tournament_start` no longer fails with
  /// "pool_phase_config required for hybrid format".
  ///
  /// `qualifiersPerGroup` mirrors the KO qualifier count when known (all teams
  /// in the single pool advance into the KO bracket up to that cut), falling
  /// back to 2 — the minimum a KO bracket can hold — when the KO config has
  /// not been chosen yet. `strategy` is `seeded` (block-fill), which is the
  /// transparent, deterministic choice for a single pool and matches the
  /// existing `seeded` examples persisted in the DB.
  static PoolPhaseConfig schochSinglePoolConfig(KoPhaseConfig? koConfig) {
    return PoolPhaseConfig(
      groupCount: 1,
      qualifiersPerGroup: koConfig?.qualifierCount ?? 2,
      strategy: PoolGroupingStrategy.seeded,
    );
  }

  /// [TournamentFormat] derived from the two-axis selection.
  TournamentFormat get derivedFormat => formatFor(vorrundeType, koType);

  /// [BracketType] derived from the two-axis selection.
  BracketType get derivedBracketType => bracketTypeFor(koType);

  /// Number of KO rounds implied by the current [koConfig] qualifier count.
  /// 0 when no qualifier count is set.
  int get koRoundCount => koRoundCountFor(koConfig?.qualifierCount ?? 0);

  /// KO bracket slot count (power of two) implied by the current [koConfig]
  /// qualifier count — the basis for the derived qualifier-per-group count
  /// (K12). 0 when fewer than two qualifiers are configured.
  static int koBracketSizeFor(int qualifierCount) {
    if (qualifierCount < 2) return 0;
    var size = 1;
    while (size < qualifierCount) {
      size <<= 1;
    }
    return size;
  }

  /// KO bracket slot count for the current [koConfig]. See [koBracketSizeFor].
  int get koBracketSize => koBracketSizeFor(koConfig?.qualifierCount ?? 0);

  /// Returns a copy whose [koRoundFormats] has exactly [koRoundCount]
  /// entries. Existing entries are preserved; new tail entries are seeded
  /// from [koMatchFormat] (falling back to [defaultKoRoundFormat]); excess
  /// entries are trimmed. Call after the qualifier count changes.
  TournamentConfigDraft withResizedKoRoundFormats() {
    final target = koRoundCount;
    if (koRoundFormats.length == target) return this;
    final seed = koMatchFormat ?? defaultKoRoundFormat;
    final next = <MatchFormatSpec>[
      for (var i = 0; i < target; i++)
        i < koRoundFormats.length ? koRoundFormats[i] : seed,
    ];
    return copyWith(koRoundFormats: List<MatchFormatSpec>.unmodifiable(next));
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

    // K09: no minimum participant validation anymore. Only the upper bound
    // (K10: up to 1000) and a non-empty roster (>= 2 to play at all) apply.
    if (maxParticipants < 2) {
      issues.add('Mindestens 2 Teilnehmer.');
    }
    if (maxParticipants > participantsHardMax) {
      issues.add('Höchstens $participantsHardMax Teilnehmer.');
    }

    if (setsToWin < setsToWinMin || setsToWin > setsToWinMax) {
      issues.add('Sätze zum Sieg muss zwischen $setsToWinMin und $setsToWinMax liegen.');
    }
    // Prelim max-sets is decoupled from setsToWin (P6: draws allowed in the
    // prelim, so even values are valid). Only a sane absolute range applies.
    if (maxSets < maxSetsMin || maxSets > maxSetsMax) {
      issues.add('Max. Sätze muss zwischen $maxSetsMin und $maxSetsMax liegen.');
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

    // K18: the consolation/Trostturnier name is required once the consolation
    // KO model is selected (it is otherwise hidden, so exempt from the rule).
    if (koType == KoType.consolation && _blankToNull(consolationName) == null) {
      issues.add('Name des Trostturniers fehlt.');
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

    // K03: the organizer must actively choose a club OR "Spasstournier –
    // ohne Wertung". A bare default draft (clubChoiceMade == false) is not
    // valid — there is no implicit "Spasstournier" default.
    if (!clubChoiceMade) {
      issues.add('Bitte einen Verein oder "Spasstournier – ohne Wertung" wählen.');
    }
    // K29: when a club is selected (i.e. NOT a Spasstournier) at least one
    // league category is required so the points/league system can dock on.
    // For a Spasstournier (clubId == null) the field is hidden, so it is
    // exempt from the required rule (K27 carve-out).
    if (clubId != null && leagueCategories.isEmpty) {
      issues.add('Bitte mindestens eine Liga-Kategorie wählen.');
    }
    // K30: venue / town is required.
    if (_blankToNull(location) == null) {
      issues.add('Ort fehlt.');
    }
    // K31: full venue address is required.
    if (_blankToNull(venueAddress) == null) {
      issues.add('Adresse fehlt.');
    }
    // K32: tournament start (date + time) is required.
    if (eventStartsAt == null) {
      issues.add('Turnierstart fehlt.');
    }
    // K33: registration deadline and on-site check-in deadline are required.
    if (registrationClosesAt == null) {
      issues.add('Anmeldeschluss fehlt.');
    }
    if (checkinUntil == null) {
      issues.add('Check-in-Zeit fehlt.');
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
      'club_id': _blankToNull(clubId),
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
      // A personal tournament (no club) is never league-relevant
      // (P6_SETUP_WIZARD_SPEC Screen 1). Defense-in-depth: even if a stale
      // selection lingers in the draft, never emit league categories without
      // a club.
      'league_categories': _blankToNull(clubId) == null
          ? const <String>[]
          : <String>[
              for (final c in leagueCategories) c.wire,
            ],
      'scoring': scoring,
      'rule_variants': ruleVariants.toJson(),
      'ko_match_format': koMatchFormat?.toJson(),
      'vorrunde_type': vorrundeType.wire,
      'ko_type': koType.wire,
      'ko_round_formats': <Map<String, Object?>>[
        for (final f in koRoundFormats) f.toJson(),
      ],
      'pitch_plan': pitchPlan?.toJson(),
      'mighty_finisher_quali': mightyFinisherQuali?.toJson(),
      // The consolation_bracket JSON carries the Model-B sizing (ADR-0028 §5):
      // direct_count + main_bracket_size are merged in from the wizard fields so
      // the server actually consumes them (otherwise the top-level keys below
      // are dropped at create-time / DOD-09). main_bracket_size is only the
      // engine-authoritative size in consolation mode; in single/double-elim it
      // is omitted (null) so the server keeps deriving from qualifier_count.
      //
      // K17: the consolation display name is merged into this jsonb as `name`
      // so it survives the create RPC (which stores `v_setup->'consolation_bracket'`
      // verbatim) and round-trips through `tournament_get` — the standalone
      // top-level `consolation_name` key below is dropped at create-time, so the
      // bracket header reads the name from `consolation_bracket.name` instead.
      'consolation_bracket': consolationBracket == null
          ? null
          : <String, Object?>{
              ...ConsolationConfig(
                enabled: consolationBracket!.enabled,
                source: consolationBracket!.source,
                sourceRounds: consolationBracket!.sourceRounds,
                rankFrom: consolationBracket!.rankFrom,
                rankTo: consolationBracket!.rankTo,
                matchFormat: consolationBracket!.matchFormat,
                directCount: consolationDirectCount,
                mainBracketSize: koType == KoType.consolation
                    ? consolationMainBracketSize
                    : null,
              ).toJson(),
              if (_blankToNull(consolationName) != null)
                'name': _blankToNull(consolationName),
            },
      // Mirrored top-level keys (kept for forward-compat / debugging).
      'consolation_main_bracket_size': consolationMainBracketSize,
      'consolation_direct_count': consolationDirectCount,
      'consolation_name': _blankToNull(consolationName),
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
          other.clubId == clubId &&
          other.clubChoiceMade == clubChoiceMade &&
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
          other.koTiebreakMethod == koTiebreakMethod &&
          other.vorrundeType == vorrundeType &&
          other.koType == koType &&
          listEquals(other.koRoundFormats, koRoundFormats) &&
          other.consolationMainBracketSize == consolationMainBracketSize &&
          other.consolationDirectCount == consolationDirectCount &&
          other.consolationName == consolationName;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        displayName,
        clubId,
        clubChoiceMade,
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
        vorrundeType,
        koType,
        Object.hashAll(koRoundFormats),
        consolationMainBracketSize,
        consolationDirectCount,
        consolationName,
      ]);
}
