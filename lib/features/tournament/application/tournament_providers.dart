import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/club/application/club_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// True when the caller may manage a tournament on the strength of its
/// *organizing club* rather than per-tournament ownership.
///
/// PER-TOURNAMENT (USER DECISION): authority is the tournament's CREATOR OR
/// an active owner/admin/organizer of THAT tournament's `club_id`. The old
/// global organizer capability (profile `is_organizer` OR owner/admin/
/// organizer of ANY club) is no longer used here — it gated almost
/// everyone, because `user_profiles.is_organizer` defaults true.
///
/// The family key is the tournament's `club_id` (null when the tournament
/// has no club). The detail screen ORs the result with the per-tournament
/// creator check, so a tournament with no club is manageable by the creator
/// only. The server is the security boundary — every lifecycle/update RPC
/// re-checks `tournament_caller_can_manage(p_tournament_id)` — so this
/// provider only governs which buttons render, never authority.
///
/// Implementation: for a non-null club the caller's roles come from
/// [clubDetailProvider] (RLS only exposes membership rows to members, so a
/// non-member organizer correctly resolves to `false`). Resolves to `false`
/// while the async club read is loading or errors, so role-gated actions
/// only appear once the role is confirmed.
// ignore: specify_nonobvious_property_types
final canManageTournamentClubProvider =
    Provider.family<bool, String?>((ref, clubId) {
  if (clubId == null) return false;
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return false;
  return ref.watch(clubDetailProvider(ClubId(clubId))).maybeWhen(
        data: (detail) => detail.members.any(
          (m) =>
              m.userId == userId &&
              (m.roles.contains('owner') ||
                  m.roles.contains('admin') ||
                  m.roles.contains('organizer')),
        ),
        orElse: () => false,
      );
});

/// One club the caller may pick as the organizing club in the setup
/// wizard: `id` is the `club_id` persisted on the tournament, `name` the
/// display label.
typedef ManageableClub = ({String id, String name});

/// The caller's clubs filtered to those they may run a tournament under,
/// i.e. where they hold an active owner/admin/organizer role. Backs the
/// optional "Ausrichtender Verein" picker in the setup wizard.
///
/// Built from [clubListProvider] (the caller's own clubs) cross-referenced
/// with each club's membership roles via [clubDetailProvider]; a club where
/// the caller is only a plain member is excluded. Empty (not an error) when
/// signed out or when the caller manages no club, so the picker simply
/// offers no clubs and the tournament stays personal. Mirrors the
/// owner/admin/organizer predicate the server's `tournament_create` enforces
/// when a `club_id` is supplied, so the picker never offers a club the RPC
/// would reject.
final manageableClubsProvider =
    FutureProvider<List<ManageableClub>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const <ManageableClub>[];
  final clubs = await ref.watch(clubListProvider.future);
  final result = <ManageableClub>[];
  for (final club in clubs) {
    final detail = await ref.watch(clubDetailProvider(ClubId(club.id)).future);
    final manages = detail.members.any(
      (m) =>
          m.userId == userId &&
          (m.roles.contains('owner') ||
              m.roles.contains('admin') ||
              m.roles.contains('organizer')),
    );
    if (manages) {
      result.add((id: club.id, name: club.displayName));
    }
  }
  return result;
});

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
          setup: draft.toSetupConfig(),
        );
    _ref.invalidate(tournamentListProvider);
    return id;
  }

  /// P7 edit-after-publish: persists the edited [draft] for an existing
  /// tournament via `tournament_update`, then invalidates the list + the
  /// detail so the screen reflects the new values. The server gates on the
  /// creator and the pre-start status.
  Future<void> updateTournament(
    TournamentId id,
    TournamentConfigDraft draft,
  ) async {
    final validation = draft.validate();
    if (!validation.isValid) {
      throw StateError(validation.issues.first);
    }
    await _ref.read(tournamentRemoteProvider).updateTournament(
          id: id,
          displayName: draft.displayName!.trim(),
          teamSize: draft.teamSize,
          minParticipants: draft.minParticipants,
          maxParticipants: draft.maxParticipants,
          format: draft.format,
          matchFormatConfig: draft.toMatchFormatConfig(),
          tiebreakerOrder: draft.tiebreakerOrder,
          setup: draft.toSetupConfig(),
        );
    _ref
      ..invalidate(tournamentListProvider)
      ..invalidate(tournamentDetailProvider(id));
  }

  Future<void> publish(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).publish(id);
    _invalidateListAndDetail(id);
  }

  Future<void> openRegistration(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).openRegistration(id);
    _invalidateListAndDetail(id);
  }

  Future<void> closeRegistration(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).closeRegistration(id);
    _invalidateListAndDetail(id);
  }

  Future<void> startTournament(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).startTournament(id);
    _invalidateListAndDetail(id);
  }

  Future<void> finalizeTournament(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).finalizeTournament(id);
    _invalidateListAndDetail(id);
  }

  Future<void> abortTournament(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).abortTournament(id);
    _invalidateListAndDetail(id);
  }

  Future<TournamentParticipantId> registerSingle(TournamentId id) async {
    final pid =
        await _ref.read(tournamentRemoteProvider).registerSingle(id);
    _invalidateListAndDetail(id);
    return pid;
  }

  /// Refresh BOTH the discovery list AND the detail of [id]. Lifecycle
  /// mutations change the tournament's status, which gates the detail
  /// screen's action buttons — without invalidating the detail provider
  /// the organizer's screen stays on the old status (e.g. stuck showing
  /// "Veröffentlichen" after publishing, never revealing "Anmeldung
  /// öffnen"). See the test-feedback fix for the publish→open-reg dead end.
  void _invalidateListAndDetail(TournamentId id) {
    _ref
      ..invalidate(tournamentListProvider)
      ..invalidate(tournamentDetailProvider(id));
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
