import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Holds the in-progress tournament configuration. Mirrors
/// `MatchConfigController`: every setter just mutates [state] and
/// downstream rebuilds happen automatically.
class TournamentConfigController extends Notifier<TournamentConfigDraft> {
  /// Optional seed for EDIT mode (P7): when non-null the controller starts
  /// from this draft (rebuilt from the tournament via
  /// [TournamentConfigDraft.fromDetail]) instead of the create-defaults.
  /// Injected through a `ProviderScope` override on the edit route so the
  /// step widgets initialise their TextEditingControllers from the prefill.
  TournamentConfigController([this._initial]);

  final TournamentConfigDraft? _initial;

  @override
  TournamentConfigDraft build() {
    final draft = _initial ?? const TournamentConfigDraft();
    // Every tournament has a KO stage now, so the legacy `format` /
    // `bracketType` must always agree with the two-axis (vorrundeType ×
    // koType) selection — even for a bare default draft that the organiser
    // never edited (it would otherwise submit as a pure round-robin without a
    // KO). Normalise on build so submit reads a consistent format.
    // Schoch always needs a single-pool config to start the hybrid format.
    // Backfill it here so an EDIT-mode draft rebuilt from a row that pre-dates
    // this fix (pool_phase_config = null) is repaired before submit.
    final poolBackfill =
        draft.vorrundeType == VorrundeType.schoch && draft.poolPhaseConfig == null
            ? TournamentConfigDraft.schochSinglePoolConfig(draft.koConfig)
            : draft.poolPhaseConfig;
    return draft.copyWith(
      format: draft.derivedFormat,
      bracketType: draft.derivedBracketType,
      poolPhaseConfig: poolBackfill,
    );
  }

  void setDisplayName(String value) {
    state = state.copyWith(displayName: value);
  }

  /// Sets (or clears, when [clubId] is null) the optional organizing club.
  /// A null club makes the tournament personal (creator-only manage).
  ///
  /// Per P6_SETUP_WIZARD_SPEC Screen 1: a personal tournament (no club) is
  /// never league-relevant. Clearing the club therefore also clears any
  /// previously picked league categories — otherwise they would linger in the
  /// draft (the chips are hidden when clubId == null) and `toSetupConfig()`
  /// would emit a non-empty `league_categories`, making a personal tournament
  /// wrongly league-relevant.
  /// K03: any selection in the picker (a club OR "Spasstournier – ohne
  /// Wertung") marks the club choice as actively made, so the Stammdaten
  /// step becomes valid. A null [clubId] therefore means the explicit
  /// Spasstournier choice, not "not chosen yet".
  void setClubId(String? clubId) {
    state = clubId == null
        ? state.copyWith(
            clearClubId: true,
            clubChoiceMade: true,
            leagueCategories: const <LeagueCategory>[],
          )
        : state.copyWith(clubId: clubId, clubChoiceMade: true);
  }

  void setMinParticipants(int value) {
    final clamped = value < TournamentConfigDraft.participantsHardMin
        ? TournamentConfigDraft.participantsHardMin
        : value;
    state = state.copyWith(minParticipants: clamped);
  }

  void setMaxParticipants(int value) {
    final clamped = value > TournamentConfigDraft.participantsHardMax
        ? TournamentConfigDraft.participantsHardMax
        : value;
    state = state.copyWith(maxParticipants: clamped);
  }

  void setFormat(TournamentFormat format) {
    // Keep the two-axis selection (vorrundeType/koType) in sync with the
    // legacy enum so either entry point stays consistent. Bracket-type
    // (single/double) is preserved when the raw enum can't express it.
    final (vorrunde, ko) = _axesFor(format, state.bracketType);
    // Mirror setVorrundeType: a Schoch Vorrunde always needs a single-pool
    // pool_phase_config so the hybrid format starts (see setVorrundeType).
    final wantsSinglePool =
        vorrunde == VorrundeType.schoch && state.poolPhaseConfig == null;
    state = state.copyWith(
      format: format,
      vorrundeType: vorrunde,
      koType: ko,
      poolPhaseConfig: wantsSinglePool
          ? TournamentConfigDraft.schochSinglePoolConfig(state.koConfig)
          : state.poolPhaseConfig,
    );
  }

  /// Reverse of [TournamentConfigDraft.formatFor]: maps a legacy enum (plus
  /// the current bracket type for the KO single/double distinction) back to
  /// the (vorrunde, ko) axes.
  (VorrundeType, KoType) _axesFor(
    TournamentFormat format,
    BracketType bracketType,
  ) {
    final ko = bracketType == BracketType.doubleElimination
        ? KoType.doubleOut
        : KoType.singleOut;
    // Every tournament has a KO stage now (the "kein KO" axis value was
    // removed). A pure prelim
    // legacy format still maps onto a hybrid axis with a single-out KO so the
    // two-axis selection stays consistent.
    return switch (format) {
      TournamentFormat.roundRobin ||
      TournamentFormat.roundRobinThenKo =>
        (VorrundeType.groupPhase, ko),
      TournamentFormat.swiss ||
      TournamentFormat.schoch ||
      TournamentFormat.singleElimination ||
      TournamentFormat.swissThenKo ||
      TournamentFormat.schochThenKo =>
        (VorrundeType.schoch, ko),
    };
  }

  /// Sets the preliminary stage axis and re-derives the legacy format.
  ///
  /// Switching to [VorrundeType.schoch] auto-initialises a single-pool
  /// [PoolPhaseConfig] (group_count == 1, all participants in one pool) when
  /// none is set yet. The Schoch Vorrunde never visits the pool-config wizard
  /// step (it is only shown for [VorrundeType.groupPhase]), so without this
  /// the hybrid `swiss_then_ko` format would persist `pool_phase_config: null`
  /// and `tournament_start` would fail with "pool_phase_config required for
  /// hybrid format" (SQLSTATE 22023). Group-phase keeps configuring the pool
  /// explicitly in its step, so only Schoch auto-fills here.
  void setVorrundeType(VorrundeType type) {
    final wantsSinglePool =
        type == VorrundeType.schoch && state.poolPhaseConfig == null;
    // Leaving Schoch for the group phase: drop the auto single-pool config so
    // the group-phase step starts clean (its UI requires group_count >= 2 and
    // would otherwise inherit the invalid group_count == 1). A user-built
    // multi-group config is preserved.
    final pool = state.poolPhaseConfig;
    final dropSinglePool = type == VorrundeType.groupPhase &&
        pool != null &&
        pool.groupCount == 1;
    state = state.copyWith(
      vorrundeType: type,
      format: TournamentConfigDraft.formatFor(type, state.koType),
      poolPhaseConfig: wantsSinglePool
          ? TournamentConfigDraft.schochSinglePoolConfig(state.koConfig)
          : (dropSinglePool ? null : state.poolPhaseConfig),
      clearPoolPhaseConfig: dropSinglePool,
    );
  }

  /// Sets the KO stage axis and re-derives the legacy format + bracket
  /// type, then resizes the per-KO-round format list. For
  /// [KoType.consolation] the consolation bracket is enabled (ADR-0028); for
  /// the other KO types it is cleared so the draft stays consistent.
  void setKoType(KoType type) {
    final existing = state.consolationBracket;
    final consolation = type == KoType.consolation
        ? ConsolationConfig(
            enabled: true,
            source: existing?.source ?? ConsolationSource.earlyKoLosers,
            sourceRounds: existing?.sourceRounds ?? const <int>[],
            rankFrom: existing?.rankFrom,
            rankTo: existing?.rankTo,
            matchFormat: existing?.matchFormat,
          )
        : null;
    state = state
        .copyWith(
          koType: type,
          format: TournamentConfigDraft.formatFor(state.vorrundeType, type),
          bracketType: TournamentConfigDraft.bracketTypeFor(type),
          consolationBracket: consolation,
          clearConsolationBracket: consolation == null,
        )
        .withResizedKoRoundFormats();
  }

  /// Replaces the per-KO-round ruleset at [index] (0 = first KO round …
  /// last = final). Out-of-range indices are ignored.
  void setKoRoundFormat(int index, MatchFormatSpec spec) {
    if (index < 0 || index >= state.koRoundFormats.length) return;
    final next = List<MatchFormatSpec>.of(state.koRoundFormats)..[index] = spec;
    state = state.copyWith(
      koRoundFormats: List<MatchFormatSpec>.unmodifiable(next),
    );
  }

  /// Sets `setsToWin` and auto-clamps `maxSets` to at least
  /// `2*setsToWin - 1`. The spec mandates max_sets >= 2*sets_to_win - 1
  /// so a series can actually be decided.
  void setSetsToWin(int value) {
    final next = value.clamp(
      TournamentConfigDraft.setsToWinMin,
      TournamentConfigDraft.setsToWinMax,
    );
    final required = 2 * next - 1;
    final nextMax = state.maxSets < required ? required : state.maxSets;
    state = state.copyWith(setsToWin: next, maxSets: nextMax);
  }

  /// Sets the prelim "Max. Sätze". Decoupled from `setsToWin` (P6 spec: the
  /// prelim allows draws, so even values like 2 are valid). Only the sane
  /// absolute range `maxSetsMin..maxSetsMax` is enforced.
  void setMaxSets(int value) {
    final next = value.clamp(
      TournamentConfigDraft.maxSetsMin,
      TournamentConfigDraft.maxSetsMax,
    );
    state = state.copyWith(maxSets: next);
  }

  void setRoundTime(int seconds) {
    state = state.copyWith(roundTimeSeconds: seconds);
  }

  void setBasekubbsPerSide(int value) {
    state = state.copyWith(basekubbsPerSide: value);
  }

  void setTiebreakerOrder(List<String> order) {
    state = state.copyWith(tiebreakerOrder: List<String>.unmodifiable(order));
  }

  /// Replaces the in-progress [KoPhaseConfig]. Used by the KO-config wizard
  /// step (T13) to commit `qualifierCount`, `withThirdPlacePlayoff` and
  /// `seedingMode` once the inputs are valid (`2 <= n <= participantCount`).
  void setKoConfig(KoPhaseConfig? config) {
    // Re-derive the per-KO-round format list whenever the qualifier count
    // (and thus the KO round count) changes.
    var next = state.copyWith(koConfig: config).withResizedKoRoundFormats();
    // C2: in consolation mode the main-bracket size and the KO qualifier count
    // denote the SAME concept ("wie viele aus der Vorrunde in den Hauptbaum").
    // Keep consolationMainBracketSize == next_pow2(qualifierCount) so the two
    // controls can never diverge (the engine consumes main_bracket_size).
    if (state.koType == KoType.consolation && config != null) {
      next = next.copyWith(
        consolationMainBracketSize: _nextPow2(config.qualifierCount),
      );
    }
    // Schoch single-pool mode: the lone pool advances exactly the KO qualifier
    // count into the bracket. The KO-config step runs AFTER the format step, so
    // (re)derive qualifiersPerGroup here. This both backfills a still-missing
    // single-pool config (e.g. when the format axis was seeded directly) and
    // keeps an existing auto single pool in step with the qualifier count. A
    // user-built multi-group config (group_count > 1) is left untouched.
    final pool = next.poolPhaseConfig;
    if (next.vorrundeType == VorrundeType.schoch &&
        config != null &&
        (pool == null || pool.groupCount == 1) &&
        pool?.qualifiersPerGroup != config.qualifierCount) {
      next = next.copyWith(
        poolPhaseConfig: PoolPhaseConfig(
          groupCount: 1,
          qualifiersPerGroup: config.qualifierCount,
          strategy: pool?.strategy ?? PoolGroupingStrategy.seeded,
          randomSeed: pool?.randomSeed,
        ),
      );
    }
    state = next;
  }

  /// Smallest power of two >= [n] (>= 2). Used to keep the consolation
  /// main-bracket size in lockstep with the KO qualifier count (C2).
  static int _nextPow2(int n) {
    var p = 1;
    while (p < n) {
      p *= 2;
    }
    return p < 2 ? 2 : p;
  }

  /// Persists the seeding source choice independent of the KO-config
  /// snapshot so the seeding-step (T11) can read it back even when the
  /// organizer hasn't touched the qualifier field yet.
  void setBracketSeedingMode(SeedingMode mode) {
    state = state.copyWith(bracketSeedingMode: mode);
  }

  void setLeagueEligible(bool value) {
    state = state.copyWith(leagueEligible: value);
  }

  // --- Model-B (consolation / Trostturnier) config (ADR-0028 §5) -------

  /// Consolation main-bracket size (power of two). Only meaningful when
  /// [KoType.consolation] is selected; persisted regardless.
  ///
  /// C2: keeps the KO qualifier count in lockstep — the main-bracket size and
  /// the qualifier count are the same concept (ADR-0028 / spec), so editing one
  /// must move the other, otherwise the wizard could persist two divergent
  /// "Hauptbaum-Grösse" values (e.g. 8 vs 4 by default).
  void setConsolationMainBracketSize(int value) {
    var next = state.copyWith(consolationMainBracketSize: value);
    final existing = state.koConfig;
    if (existing != null && existing.qualifierCount != value) {
      next = next
          .copyWith(
            koConfig: KoPhaseConfig(
              qualifierCount: value,
              participantCount: existing.participantCount,
              withThirdPlacePlayoff: existing.withThirdPlacePlayoff,
              seedingMode: existing.seedingMode,
            ),
          )
          .withResizedKoRoundFormats();
    }
    state = next;
  }

  /// Number of prelim teams that start directly in the consolation bracket
  /// (free integer >= 0).
  void setConsolationDirectCount(int value) {
    state = state.copyWith(consolationDirectCount: value < 0 ? 0 : value);
  }

  /// Free display name of the consolation/Trostturnier.
  void setConsolationName(String? value) {
    final trimmed = value?.trim();
    state = state.copyWith(
      consolationName: trimmed,
      clearConsolationName: trimmed == null || trimmed.isEmpty,
    );
  }

  // --- P6 Stammdaten setters (Phase 1b) ---

  void setLocation(String value) {
    state = state.copyWith(location: value);
  }

  void setVenueAddress(String value) {
    state = state.copyWith(venueAddress: value);
  }

  void setEventStartsAt(DateTime value) {
    state = state.copyWith(eventStartsAt: value);
  }

  void setCheckinUntil(DateTime value) {
    state = state.copyWith(checkinUntil: value);
  }

  void setRegistrationClosesAt(DateTime value) {
    state = state.copyWith(registrationClosesAt: value);
  }

  /// `ekc` or `classic`.
  void setScoring(String value) {
    state = state.copyWith(scoring: value);
  }

  /// Toggles one league tier on/off, keeping the list in A,B,C order.
  void toggleLeagueCategory(LeagueCategory category) {
    final next = List<LeagueCategory>.of(state.leagueCategories);
    if (next.contains(category)) {
      next.remove(category);
    } else {
      next
        ..add(category)
        ..sort((a, b) => a.index.compareTo(b.index));
    }
    state = state.copyWith(
      leagueCategories: List<LeagueCategory>.unmodifiable(next),
    );
  }

  /// Participation fee in cents. Pass `null` to mark the tournament free.
  void setEntryFeeCents(int? cents) {
    state = state.copyWith(
      entryFeeCents: cents,
      clearEntryFeeCents: cents == null,
    );
  }

  /// Toggles one payment method (`cash` / `twint` / `card`).
  void togglePaymentMethod(String method) {
    final next = List<String>.of(state.paymentMethods);
    if (next.contains(method)) {
      next.remove(method);
    } else {
      next.add(method);
    }
    state = state.copyWith(paymentMethods: List<String>.unmodifiable(next));
  }

  void setContactName(String value) {
    state = state.copyWith(contactName: value);
  }

  void setContactPhone(String value) {
    state = state.copyWith(contactPhone: value);
  }

  void setInfoFood(String value) {
    state = state.copyWith(infoFood: value);
  }

  void setInfoTravel(String value) {
    state = state.copyWith(infoTravel: value);
  }

  void setInfoAccommodation(String value) {
    state = state.copyWith(infoAccommodation: value);
  }

  void setWeatherNote(String value) {
    state = state.copyWith(weatherNote: value);
  }

  void setRuleVariants(RuleVariants variants) {
    state = state.copyWith(ruleVariants: variants);
  }

  void setRulesPdfUrl(String? url) {
    state = state.copyWith(rulesPdfUrl: url, clearRulesPdfUrl: url == null);
  }

  void setSiteMapPdfUrl(String? url) {
    state = state.copyWith(
      siteMapPdfUrl: url,
      clearSiteMapPdfUrl: url == null,
    );
  }

  // --- P6 Phase 2: Vorrunde + Pitches ---

  /// Minimum players per team (1 = singles). Clamped to 1..6; pulls the
  /// maximum up so it never falls below the minimum.
  void setTeamSize(int value) {
    final min = value.clamp(1, 6);
    final max = state.maxTeamSize < min ? min : state.maxTeamSize;
    state = state.copyWith(teamSize: min, maxTeamSize: max);
  }

  /// Maximum players per team. Clamped to the current minimum..6.
  void setMaxTeamSize(int value) {
    state = state.copyWith(maxTeamSize: value.clamp(state.teamSize, 6));
  }

  /// Replaces the pitch plan. Pass `null` to clear it (pitches can be
  /// configured later, before the tournament starts).
  void setPitchPlan(PitchPlan? plan) {
    state = state.copyWith(pitchPlan: plan, clearPitchPlan: plan == null);
  }

  /// Prelim tiebreak trigger in seconds; `null` = no prelim tiebreak.
  void setPrelimTiebreakAfterSeconds(int? seconds) {
    state = state.copyWith(
      prelimTiebreakAfterSeconds: seconds,
      clearPrelimTiebreak: seconds == null,
    );
  }

  void setBreakBetweenMatchesSeconds(int seconds) {
    state = state.copyWith(
      breakBetweenMatchesSeconds: seconds < 0 ? 0 : seconds,
    );
  }

  // --- P6 Phase 3: Bracket / KO ---

  void setBracketType(BracketType type) {
    state = state.copyWith(bracketType: type);
  }

  void setKoMatchup(KoMatchup matchup) {
    state = state.copyWith(koMatchup: matchup);
  }

  void setKoTiebreakMethod(KoTiebreakMethod method) {
    state = state.copyWith(koTiebreakMethod: method);
  }

  void setKoMatchFormat(MatchFormatSpec? format) {
    state = state.copyWith(
      koMatchFormat: format,
      clearKoMatchFormat: format == null,
    );
  }

  void setConsolationBracket(ConsolationConfig? config) {
    state = state.copyWith(
      consolationBracket: config,
      clearConsolationBracket: config == null,
    );
  }

  /// Replaces the in-progress [PoolPhaseConfig] (T9). Pass `null` to clear
  /// it — the [TournamentConfigDraft.copyWith] sentinel `clearPoolPhaseConfig`
  /// makes the field nullable across edits, which is what the pool-toggle
  /// off-state needs.
  void setPoolPhaseConfig(PoolPhaseConfig? config) {
    state = state.copyWith(
      poolPhaseConfig: config,
      clearPoolPhaseConfig: config == null,
    );
  }

  TournamentConfigValidation validate() => state.validate();

  void reset() {
    state = const TournamentConfigDraft();
  }
}
