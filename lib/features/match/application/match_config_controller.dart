import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/match/data/match_config_draft.dart';
import 'package:kubb_app/features/match/data/match_models.dart';

/// Holds the in-progress match configuration. The wizard mutates this
/// via the methods below; downstream providers (validation, summary
/// preview) rebuild on each `state =` assignment.
class MatchConfigController extends Notifier<MatchConfigDraft> {
  @override
  MatchConfigDraft build() {
    // Pre-seed the caller as the first member of team A so the user
    // never lands on an "add yourself first" empty wizard.
    return const MatchConfigDraft(teamA: <TeamSlot>[SelfSlot()]);
  }

  void setFormat(MatchFormat format) {
    state = state.copyWith(format: format);
  }

  /// Adds [slot] to [team]. If the slot already exists in the *other*
  /// team it is moved (a slot can only live in one team at a time).
  void addToTeam(TeamSlot slot, MatchTeamTag team) {
    final existing = state.teamOf(slot);
    if (existing == team) return;
    final cleaned = _withoutSlot(slot);
    state = _appendToTeam(cleaned, slot, team);
  }

  void removeFromTeam(TeamSlot slot) {
    state = _withoutSlot(slot);
  }

  void moveToTeam(TeamSlot slot, MatchTeamTag newTeam) {
    addToTeam(slot, newTeam);
  }

  MatchConfigValidation validate() => state.validate();

  /// Resets the draft back to its initial state (caller in team A,
  /// team B empty, defaults for format/scoring).
  void reset() {
    state = const MatchConfigDraft(teamA: <TeamSlot>[SelfSlot()]);
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  MatchConfigDraft _withoutSlot(TeamSlot slot) {
    final filteredA = state.teamA
        .where((s) => s.localId != slot.localId)
        .toList(growable: false);
    final filteredB = state.teamB
        .where((s) => s.localId != slot.localId)
        .toList(growable: false);
    return state.copyWith(teamA: filteredA, teamB: filteredB);
  }

  MatchConfigDraft _appendToTeam(
    MatchConfigDraft draft,
    TeamSlot slot,
    MatchTeamTag team,
  ) {
    switch (team) {
      case MatchTeamTag.a:
        return draft.copyWith(
          teamA: <TeamSlot>[...draft.teamA, slot],
        );
      case MatchTeamTag.b:
        return draft.copyWith(
          teamB: <TeamSlot>[...draft.teamB, slot],
        );
    }
  }
}

final NotifierProvider<MatchConfigController, MatchConfigDraft>
    matchConfigControllerProvider =
    NotifierProvider.autoDispose<MatchConfigController, MatchConfigDraft>(
  MatchConfigController.new,
);
