import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Holds the in-progress tournament configuration. Mirrors
/// `MatchConfigController`: every setter just mutates [state] and
/// downstream rebuilds happen automatically.
class TournamentConfigController extends Notifier<TournamentConfigDraft> {
  @override
  TournamentConfigDraft build() => const TournamentConfigDraft();

  void setDisplayName(String value) {
    state = state.copyWith(displayName: value);
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
    state = state.copyWith(format: format);
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

  void setMaxSets(int value) {
    final floor = 2 * state.setsToWin - 1;
    final next = value < floor ? floor : value;
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
    state = state.copyWith(koConfig: config);
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
