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
    // K12: a group-phase draft equally needs a valid pool config; seed the
    // default (group_count == 4) so the Vorrunde step shows the default and
    // submit always carries a valid pool_phase_config for the hybrid format.
    final PoolPhaseConfig? poolBackfill;
    if (draft.poolPhaseConfig != null) {
      poolBackfill = draft.poolPhaseConfig;
    } else if (draft.vorrundeType == VorrundeType.schoch) {
      poolBackfill = TournamentConfigDraft.schochSinglePoolConfig(draft.koConfig);
    } else {
      poolBackfill = PoolPhaseConfig(
        groupCount: 4,
        qualifiersPerGroup:
            _derivedQualifiersPerGroup(draft.koBracketSize, 4),
        strategy: PoolGroupingStrategy.snake,
      );
    }
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
        // Picking a club makes the tournament a rated league event, where the
        // "auf Einladung" option does not apply (invite-only is Spaßturnier-
        // only). Reset the flag + any pending invitees so a stale selection
        // can't leak into a club tournament.
        : state.copyWith(
            clubId: clubId,
            clubChoiceMade: true,
            inviteOnly: false,
            invitedUsers: const <InvitedUser>[],
          );
  }

  /// Toggles the Spaßturnier "auf Einladung" flag. Turning it off also clears
  /// any already-picked invitees so they are not silently sent if the organizer
  /// re-enables the toggle later.
  void setInviteOnly(bool value) {
    state = value
        ? state.copyWith(inviteOnly: true)
        : state.copyWith(
            inviteOnly: false,
            invitedUsers: const <InvitedUser>[],
          );
  }

  /// Adds a player to the invite list. No-op when the same [InvitedUser.userId]
  /// is already present (dedupe by user id).
  void addInvitee(InvitedUser invitee) {
    if (state.invitedUsers.any((u) => u.userId == invitee.userId)) return;
    state = state.copyWith(
      invitedUsers: <InvitedUser>[...state.invitedUsers, invitee],
    );
  }

  /// Removes the invitee with [userId] from the invite list.
  void removeInvitee(String userId) {
    state = state.copyWith(
      invitedUsers: <InvitedUser>[
        for (final u in state.invitedUsers)
          if (u.userId != userId) u,
      ],
    );
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
    // Reseed when the current config is not already a single pool (a lingering
    // group-phase multi-group config, K12).
    final wantsSinglePool = vorrunde == VorrundeType.schoch &&
        (state.poolPhaseConfig == null ||
            state.poolPhaseConfig!.groupCount != 1);
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
      TournamentFormat.schoch ||
      TournamentFormat.singleElimination ||
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
  /// the hybrid `schoch_then_ko` format would persist `pool_phase_config: null`
  /// and `tournament_start` would fail with "pool_phase_config required for
  /// hybrid format" (SQLSTATE 22023). Group-phase keeps configuring the pool
  /// explicitly in its step, so only Schoch auto-fills here.
  void setVorrundeType(VorrundeType type) {
    // Schoch always runs as a single pool (group_count == 1). Seed/replace the
    // pool config whenever the current one is not already a single pool — the
    // group phase may have left a multi-group config behind (K12).
    final wantsSinglePool = type == VorrundeType.schoch &&
        (state.poolPhaseConfig == null ||
            state.poolPhaseConfig!.groupCount != 1);
    // K12: the group phase now configures groups directly in the Vorrunde
    // step, so switching INTO the group phase seeds a default multi-group
    // config (group_count == 4) when none exists yet or when only the Schoch
    // single-pool (group_count == 1) lingers — the group-phase UI requires
    // group_count >= 2. A user-built multi-group config (group_count > 1) is
    // preserved.
    final pool = state.poolPhaseConfig;
    final needsGroupDefault = type == VorrundeType.groupPhase &&
        (pool == null || pool.groupCount < 2);
    final groupDefault = PoolPhaseConfig(
      groupCount: 4,
      qualifiersPerGroup:
          _derivedQualifiersPerGroup(state.koBracketSize, 4),
      strategy: pool?.strategy ?? PoolGroupingStrategy.snake,
      randomSeed: pool?.strategy == PoolGroupingStrategy.random
          ? pool?.randomSeed
          : null,
    );
    state = state.copyWith(
      vorrundeType: type,
      format: TournamentConfigDraft.formatFor(type, state.koType),
      poolPhaseConfig: wantsSinglePool
          ? TournamentConfigDraft.schochSinglePoolConfig(state.koConfig)
          : (needsGroupDefault ? groupDefault : state.poolPhaseConfig),
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
    // keeps an existing auto single pool in step with the qualifier count.
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
    } else if (next.vorrundeType == VorrundeType.groupPhase &&
        config != null &&
        pool != null &&
        pool.groupCount > 0) {
      // K12: group-phase qualifiers-per-group is derived from the KO bracket
      // size / group count. The Vorrunde step gathers group count + strategy
      // BEFORE the KO size is known, so re-derive the qualifier count here once
      // the KO config is committed. Only update when it actually changes so the
      // strategy/seed the organiser picked are preserved.
      final derived =
          _derivedQualifiersPerGroup(next.koBracketSize, pool.groupCount);
      if (pool.qualifiersPerGroup != derived) {
        next = next.copyWith(
          poolPhaseConfig: PoolPhaseConfig(
            groupCount: pool.groupCount,
            qualifiersPerGroup: derived,
            strategy: pool.strategy,
            randomSeed: pool.randomSeed,
          ),
        );
      }
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

  /// K12: sets the group-phase grouping inputs (group count + strategy +
  /// optional random seed) gathered directly in the Vorrunde step. The
  /// "Qualifier pro Gruppe" count stays DERIVED, not an input: it is
  /// `koBracketSize / groupCount` when the KO size is already known and the
  /// group count divides it evenly, otherwise a provisional `1` (the KO step
  /// runs after the Vorrunde step and re-derives the value in [setKoConfig]).
  ///
  /// The `randomSeed` is only carried for [PoolGroupingStrategy.random].
  void setPoolGrouping({
    required int groupCount,
    required PoolGroupingStrategy strategy,
    int? randomSeed,
  }) {
    state = state.copyWith(
      poolPhaseConfig: PoolPhaseConfig(
        groupCount: groupCount,
        qualifiersPerGroup: _derivedQualifiersPerGroup(
          state.koBracketSize,
          groupCount,
        ),
        strategy: strategy,
        randomSeed:
            strategy == PoolGroupingStrategy.random ? randomSeed : null,
      ),
    );
  }

  /// Derives the qualifier-per-group count from the KO bracket size and the
  /// group count (K12). Returns the provisional minimum `1` when the KO size
  /// is unknown or the group count does not evenly divide it — the actual
  /// divisibility gate lives in the wizard step validation.
  static int _derivedQualifiersPerGroup(int koBracketSize, int groupCount) {
    if (groupCount < 1 || koBracketSize <= 0) return 1;
    if (koBracketSize % groupCount != 0) return 1;
    return koBracketSize ~/ groupCount;
  }

  // --- P2.1: stage-graph format axis (ADR-0033) ------------------------

  /// Sets the top-level format axis (classic vs. stage-graph). Only mutates
  /// [TournamentConfigDraft.formatMode]; the classic Vorrunde × KO fields and
  /// the separately-held [TournamentConfigDraft.stageGraph] are preserved, so a
  /// mode switch never discards either path's data (PLAN §4 risk hedge).
  void setFormatMode(TournamentFormatMode mode) {
    state = state.copyWith(formatMode: mode);
  }

  /// Sets the built/picked stage graph. Held separately from koConfig /
  /// vorrundeType, so this does not touch the classic axis.
  void setStageGraph(StageGraph graph) {
    state = state.copyWith(stageGraph: graph);
  }

  /// Binds the draft to a saved/system template (P2.4). When set, submit applies
  /// that template directly instead of auto-saving the free graph as a private
  /// duplicate. Pass null when the organizer edits the graph manually so the
  /// stale template reference does not leak into submit.
  void setAppliedTemplateId(String? id) {
    state = state.copyWith(
      appliedTemplateId: id,
      clearAppliedTemplateId: id == null,
    );
  }

  /// Clears the stage graph (and the applied template id it logically belongs
  /// to), e.g. when the organizer abandons the graph path. Leaves the classic
  /// Vorrunde × KO fields untouched.
  void clearStageGraph() {
    state = state.copyWith(
      clearStageGraph: true,
      clearAppliedTemplateId: true,
    );
  }

  /// Sets the Schoch round count (M4 #3 / ADR-0039 §5). The wizard's Schoch
  /// section clamps the input to its 5..9 band before calling this; the draft
  /// carries the value into the Schoch stage node's `config['rounds']` on
  /// submit so it survives a save.
  void setSchochRounds(int rounds) {
    state = state.copyWith(schochRounds: rounds);
  }

  TournamentConfigValidation validate() => state.validate();

  void reset() {
    state = const TournamentConfigDraft();
  }
}
