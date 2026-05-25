import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
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
}
