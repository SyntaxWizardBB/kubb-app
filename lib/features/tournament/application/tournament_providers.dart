import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Wizard-side config notifier. Auto-disposes so a freshly opened wizard
/// always starts from defaults — even after a cancelled previous run.
final NotifierProvider<TournamentConfigController, TournamentConfigDraft>
    tournamentConfigControllerProvider = NotifierProvider.autoDispose<
        TournamentConfigController, TournamentConfigDraft>(
  TournamentConfigController.new,
);

/// Caller's tournaments (list view backing provider). Empty surface while
/// not authenticated keeps the home/list screens trivial.
final tournamentListProvider =
    FutureProvider<List<TournamentSummaryRef>>((ref) async {
  return ref.read(tournamentRemoteProvider).listTournaments();
});

/// Imperative action surface mirroring `matchActionsProvider`: keeps the
/// invalidate-after-write plumbing out of widget code.
final tournamentActionsProvider = Provider<TournamentActions>((ref) {
  return TournamentActions(ref);
});

/// Thin facade over [TournamentRemote] used by the wizard and the
/// organizer screens. Each lifecycle method invalidates the list view so
/// status changes show up immediately.
class TournamentActions {
  TournamentActions(this._ref);
  final Ref _ref;

  Future<TournamentId> createTournament(TournamentConfigDraft draft) async {
    final validation = draft.validate();
    if (!validation.isValid) {
      throw StateError(validation.issues.first);
    }
    final id = await _ref.read(tournamentRemoteProvider).createTournament(
          displayName: draft.displayName!.trim(),
          teamSize: draft.teamSize,
          minParticipants: draft.minParticipants,
          maxParticipants: draft.maxParticipants,
          format: draft.format,
          matchFormatConfig: draft.toMatchFormatConfig(),
          tiebreakerOrder: draft.tiebreakerOrder,
        );
    _ref.invalidate(tournamentListProvider);
    return id;
  }

  Future<void> publish(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).publish(id);
    _ref.invalidate(tournamentListProvider);
  }

  Future<void> openRegistration(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).openRegistration(id);
    _ref.invalidate(tournamentListProvider);
  }

  Future<void> closeRegistration(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).closeRegistration(id);
    _ref.invalidate(tournamentListProvider);
  }

  Future<void> startTournament(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).startTournament(id);
    _ref.invalidate(tournamentListProvider);
  }

  Future<void> finalizeTournament(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).finalizeTournament(id);
    _ref.invalidate(tournamentListProvider);
  }

  Future<void> abortTournament(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).abortTournament(id);
    _ref.invalidate(tournamentListProvider);
  }

  Future<TournamentParticipantId> registerSingle(TournamentId id) async {
    final pid =
        await _ref.read(tournamentRemoteProvider).registerSingle(id);
    _ref.invalidate(tournamentListProvider);
    return pid;
  }

  Future<void> withdrawRegistration(TournamentParticipantId id) async {
    await _ref.read(tournamentRemoteProvider).withdrawRegistration(id);
    _ref.invalidate(tournamentListProvider);
  }

  Future<void> confirmRegistration(TournamentParticipantId id) async {
    await _ref.read(tournamentRemoteProvider).confirmRegistration(id);
    _ref.invalidate(tournamentListProvider);
  }

  Future<void> rejectRegistration(TournamentParticipantId id) async {
    await _ref.read(tournamentRemoteProvider).rejectRegistration(id);
    _ref.invalidate(tournamentListProvider);
  }

  /// Organizer override for a disputed match. Persists the final score
  /// and the mandatory reason via the `tournament_organizer_override`
  /// RPC, then nudges the list so the row flips to `overridden`.
  Future<void> organizerOverride({
    required TournamentMatchId matchId,
    required List<SetScore> finalSetScores,
    required String reason,
  }) async {
    await _ref.read(tournamentRemoteProvider).organizerOverride(
          matchId: matchId,
          finalSetScores: finalSetScores,
          reason: reason,
        );
    _ref.invalidate(tournamentListProvider);
  }

  /// Submits one team's proposal for the scores of all sets of a match
  /// in the given consensus retry round. Refreshes the affected match
  /// detail so the screen picks up the new consensus state / status.
  Future<void> proposeSetScores({
    required TournamentMatchId matchId,
    required int consensusRound,
    required List<SetScore> setScores,
  }) async {
    await _ref.read(tournamentRemoteProvider).proposeSetScores(
          matchId: matchId,
          consensusRound: consensusRound,
          setScores: setScores,
        );
    _ref.invalidate(tournamentMatchDetailProvider(matchId));
  }

  /// W3-T1 / DSCORE-62..-66: organizer declares a no-show forfeit on
  /// behalf of the absent side. Server validates the status gate, the
  /// reason length and writes the audit-event hook. Refreshes the match
  /// detail so the screen picks up the `finalized` state immediately.
  Future<void> declareForfeit({
    required TournamentMatchId matchId,
    required ForfeitAbsentSide absentSide,
    required String reason,
  }) async {
    await _ref.read(tournamentRemoteProvider).declareForfeit(
          matchId: matchId,
          absentSide: absentSide,
          reason: reason,
        );
    _ref.invalidate(tournamentMatchDetailProvider(matchId));
  }
}
