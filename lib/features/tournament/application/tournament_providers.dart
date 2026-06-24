import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/application/outbox_flusher_provider.dart'
    show outboxFlusherProvider;
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/organizer_team/application/organizer_team_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// True when the caller may SET UP a tournament on the strength of its
/// *organizing club* rather than per-tournament ownership.
///
/// SETUP-GATE MIRROR (gate split, migration `20261281000000`): the club-role
/// half of the server gate `tournament_caller_can_setup` = Creator OR an
/// active club role in exactly {owner, admin}. Referees are deliberately NOT
/// in this set — they may administer a live tournament (see
/// [canAdministerTournamentProvider]) but never change its structure or
/// lifecycle (update/publish/start/registration/seeding).
///
/// The family key is the tournament's `club_id` (null when the tournament
/// has no club). The detail screen ORs the result with the per-tournament
/// creator check, so a tournament with no club is manageable by the creator
/// only. The server is the security boundary — every lifecycle/update RPC
/// re-checks `tournament_caller_can_setup(p_tournament_id)` — so this
/// provider only governs which buttons render, never authority.
///
/// Implementation: for a non-null club the caller's roles come from
/// [organizerTeamDetailProvider] (RLS only exposes membership rows to members, so a
/// non-member correctly resolves to `false`). Resolves to `false` while the
/// async club read is loading or errors, so role-gated actions only appear
/// once the role is confirmed.
// ignore: specify_nonobvious_property_types
final canManageTournamentClubProvider =
    Provider.family<bool, String?>((ref, clubId) {
  if (clubId == null) return false;
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return false;
  return ref.watch(organizerTeamDetailProvider(OrganizerTeamId(clubId))).maybeWhen(
        data: (detail) => detail.members.any(
          (m) =>
              m.userId == userId &&
              (m.roles.contains('owner') || m.roles.contains('admin')),
        ),
        orElse: () => false,
      );
});

/// Family key for [canAdministerTournamentProvider]: the tournament's
/// organizing `clubId` (null when the tournament has no club) plus its
/// `createdBy` user id (the creator). Both are carried on the
/// [TournamentDetail] the dashboard already holds (the dashboard maps that
/// detail to this key), so the gate needs no extra fetch. Note: the overview
/// DTO [TournamentAdminCardRef] does NOT project these fields — they come
/// from the detail read.
typedef AdministrableGateKey = ({String? clubId, String? createdBy});

/// True when the caller may ADMINISTER a tournament from the organizer
/// dashboard (ADR-0031 Phase B, Block B1c — K4 gate).
///
/// Access = Creator OR an active club role in {owner, admin, referee}.
/// This mirrors [canManageTournamentClubProvider] but ADDS `referee` to the
/// role set (that provider only checks owner/admin) and ORs in the
/// per-tournament creator check. The role set is exactly the server gate
/// `tournament_caller_can_administer` (`ARRAY['owner','admin','referee']`,
/// gate split migration `20261281000000`), so the client mirrors the
/// server 1:1.
///
/// Resolves to `false` when not authenticated, while the async club read is
/// loading, and on error — a role-gated action only appears once the role is
/// confirmed. The server stays the security boundary (every control RPC
/// re-checks the gate); this provider only governs button / visibility.
// ignore: specify_nonobvious_property_types
final canAdministerTournamentProvider =
    Provider.family<bool, AdministrableGateKey>((ref, key) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return false;
  // Creator branch: the tournament's creator may always administer it,
  // independent of any club role (a personal tournament has no club).
  if (key.createdBy != null && key.createdBy == userId) return true;
  final clubId = key.clubId;
  if (clubId == null) return false;
  return ref.watch(organizerTeamDetailProvider(OrganizerTeamId(clubId))).maybeWhen(
        data: (detail) => detail.members.any(
          (m) =>
              m.userId == userId &&
              (m.roles.contains('owner') ||
                  m.roles.contains('admin') ||
                  m.roles.contains('referee')),
        ),
        orElse: () => false,
      );
});

/// One club the caller may pick as the organizing club in the setup
/// wizard: `id` is the `club_id` persisted on the tournament, `name` the
/// display label.
typedef ManageableClub = ({String id, String name});

/// The caller's clubs filtered to those they may run a tournament under,
/// i.e. where they hold an active role in exactly {owner, admin}. Backs the
/// optional "Ausrichtender Verein" picker in the setup wizard.
///
/// Referee-only clubs are deliberately EXCLUDED: a referee may administer a
/// live tournament but never set one up (setup gate, migration
/// `20261281000000`), so the picker must not offer such a club.
///
/// Built from [organizerTeamListProvider] (the caller's own clubs) cross-referenced
/// with each club's membership roles via [organizerTeamDetailProvider]; a club where
/// the caller is only a plain member or only a referee is excluded. Empty
/// (not an error) when signed out or when the caller manages no club, so
/// the picker simply offers no clubs and the tournament stays personal.
/// Mirrors the owner/admin predicate the server's `tournament_create`
/// effectively enforces when a `club_id` is supplied, so the picker never
/// offers a club the RPC would reject.
final manageableClubsProvider =
    FutureProvider<List<ManageableClub>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const <ManageableClub>[];
  final clubs = await ref.watch(organizerTeamListProvider.future);
  final result = <ManageableClub>[];
  for (final club in clubs) {
    final detail = await ref.watch(organizerTeamDetailProvider(OrganizerTeamId(club.id)).future);
    final manages = detail.members.any(
      (m) =>
          m.userId == userId &&
          (m.roles.contains('owner') || m.roles.contains('admin')),
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

/// Tournaments the caller may administer, backing the organizer dashboard
/// overview (ADR-0031 Phase B, Block B1c). One `tournament_list_administrable`
/// RPC (server-gated to Creator + {owner,admin,referee}); the
/// projection carries phase/round/schedule status, remaining seconds and the
/// open/disputed match counts.
///
/// NO `Timer.periodic` / polling for server-state discovery (ADR-0029 /
/// OE-B3): this overview has no single-column user scope, so its realtime
/// refresh is driven later by Inbox-CDC invalidation, not by a poll loop.
final administrableTournamentsProvider =
    FutureProvider<List<TournamentAdminCardRef>>((ref) async {
  return ref.read(tournamentRemoteProvider).listAdministrableTournaments();
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
          // K01: persist the name with the year suffix appended (idempotent).
          displayName: draft.resolvedDisplayName!,
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

  /// P7 / V2-B2 edit-after-publish (incl. live): persists the edited [draft]
  /// for an existing tournament via `tournament_update`, then invalidates the
  /// list + detail so the screen reflects the new values. Because a LIVE edit
  /// can make the server re-generate the unplayed pairings/bracket of the
  /// affected phase (migration 20261243000000), the match list, standings and
  /// bracket providers are invalidated too so those views reload the
  /// recomputed state. The server gates on the creator/admin and the status.
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
          // K01: persist the name with the year suffix appended (idempotent).
          displayName: draft.resolvedDisplayName!,
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
      ..invalidate(tournamentDetailProvider(id))
      // A live structural edit may regenerate the unplayed pairings/bracket.
      ..invalidate(tournamentMatchListProvider(id))
      ..invalidate(tournamentStandingsProvider(id))
      ..invalidate(tournamentBracketProvider(id));
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

  /// Brings an aborted tournament back to the status it had before the abort.
  /// Refreshes list + detail so the status-gated buttons re-render.
  Future<void> reactivate(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).reactivateTournament(id);
    _invalidateListAndDetail(id);
  }

  Future<TournamentParticipantId> registerSingle(TournamentId id) async {
    final pid =
        await _ref.read(tournamentRemoteProvider).registerSingle(id);
    _invalidateListAndDetail(id);
    _ref.invalidate(myTournamentRegistrationsProvider);
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

  /// Self-withdraw. Refreshes the discovery list AND the "Angemeldete
  /// Turniere" list ([myTournamentRegistrationsProvider]) so the tournament
  /// drops out of the caller's registrations and the tile flips back to
  /// "Anmelden". Pass [tournamentId] (the participant's tournament) so the
  /// detail screen flips "Abmelden" → "Anmelden" immediately too.
  Future<void> withdrawRegistration(
    TournamentParticipantId id, {
    TournamentId? tournamentId,
  }) async {
    await _ref.read(tournamentRemoteProvider).withdrawRegistration(id);
    _ref
      ..invalidate(tournamentListProvider)
      ..invalidate(myTournamentRegistrationsProvider);
    if (tournamentId != null) {
      _ref.invalidate(tournamentDetailProvider(tournamentId));
    }
  }

  /// On-site check-in (ADR-0031 Phase D, Block D3). Marks a confirmed
  /// participant as physically present via the `tournament_checkin_participant`
  /// RPC, then invalidates [tournamentDetailProvider] for [tournamentId] so the
  /// participant list re-reads with the new `checked_in_at` — analogous to
  /// [withdrawRegistration]. The server owns the manage gate / status window
  /// (K4); this method does not duplicate that logic. The realtime CDC stream
  /// also drives the same invalidation; this explicit re-read keeps the
  /// initiating device responsive without waiting for the round-trip.
  Future<void> checkin(
    TournamentParticipantId id, {
    required TournamentId tournamentId,
  }) async {
    await _ref.read(tournamentRemoteProvider).checkinParticipant(id);
    _ref.invalidate(tournamentDetailProvider(tournamentId));
  }

  /// Reverts an on-site check-in (ADR-0031 Phase D, Block D3) via the
  /// `tournament_undo_checkin` RPC, then invalidates [tournamentDetailProvider]
  /// for [tournamentId]. Same server-authoritative gate as [checkin].
  Future<void> undoCheckin(
    TournamentParticipantId id, {
    required TournamentId tournamentId,
  }) async {
    await _ref.read(tournamentRemoteProvider).undoCheckin(id);
    _ref.invalidate(tournamentDetailProvider(tournamentId));
  }

  /// Cross-tournament check-in search (spec §7 / §9.6). Forwards the query to
  /// `tournament_search_checkin_targets`; the server scopes the hits to the
  /// caller-administered, public, check-in-phase tournaments, so this method
  /// adds no client-side filtering.
  Future<List<CheckinSearchHit>> searchCheckinTargets(String query) =>
      _ref.read(tournamentRemoteProvider).searchCheckinTargets(query);

  /// Checks a cross-tournament search hit in via the existing
  /// `tournament_checkin_participant` RPC (server owns the gate / status
  /// window). Invalidates the hit's own tournament detail so an open detail
  /// view re-reads the presence; the cross-checkin screen drives its own list
  /// refresh on top of this.
  Future<void> checkinTarget(CheckinSearchHit hit) async {
    await _ref.read(tournamentRemoteProvider).checkinParticipant(
          hit.participantId,
        );
    _ref.invalidate(tournamentDetailProvider(hit.tournamentId));
  }

  Future<void> confirmRegistration(TournamentParticipantId id) async {
    await _ref.read(tournamentRemoteProvider).confirmRegistration(id);
    _ref.invalidate(tournamentListProvider);
  }

  Future<void> rejectRegistration(TournamentParticipantId id) async {
    await _ref.read(tournamentRemoteProvider).rejectRegistration(id);
    _ref.invalidate(tournamentListProvider);
  }

  /// Organizer remove of a confirmed or waitlisted participant via
  /// `tournament_remove_participant`. Soft-removes the row and promotes the
  /// next waitlisted entry into the freed slot (server-side). Invalidates the
  /// detail + discovery list AND the standings, because the promotion shifts
  /// the confirmed pool the standings are computed over. The server owns the
  /// setup gate and the status window; this method does not duplicate them.
  Future<void> removeParticipant(
    TournamentParticipantId id, {
    required TournamentId tournamentId,
    String? reason,
  }) async {
    await _ref
        .read(tournamentRemoteProvider)
        .removeParticipant(id, reason: reason);
    _ref
      ..invalidate(tournamentDetailProvider(tournamentId))
      ..invalidate(tournamentListProvider)
      ..invalidate(tournamentStandingsProvider(tournamentId));
  }

  /// Organizer override for a match. Persists the final score and the
  /// mandatory reason via the `tournament_organizer_override` RPC, then
  /// refreshes the affected match detail so the acting device flips to
  /// `overridden` immediately (mirrors [proposeSetScores] / [declareForfeit];
  /// otherwise the organizer would keep seeing the pre-override status until
  /// the realtime CDC event — or the 30s fallback poll — catches up). The
  /// list is nudged too so its row reflects the finalised result.
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
    _ref
      ..invalidate(tournamentMatchDetailProvider(matchId))
      ..invalidate(tournamentListProvider);
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
    // Kick off the flush from the action's ref: the repository can't do it
    // itself without forming a remote↔flusher provider cycle. Fire-and-forget
    // so a network failure inside the flush doesn't abort the submit — the
    // row is durably enqueued and the flusher retries on reconnect.
    unawaited(_ref.read(outboxFlusherProvider).flushPending());
    _ref.invalidate(tournamentMatchDetailProvider(matchId));
  }

  /// ADR-0031 Phase B (Block B2c): tournament-wide pause. Calls the
  /// `tournament_pause` control RPC via the port, then refreshes the
  /// dashboard overview. See [_invalidateScheduleControlOverview] for why the
  /// detail schedule is intentionally NOT invalidated here.
  Future<void> pause(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).pauseTournament(id);
    _invalidateScheduleControlOverview();
  }

  /// ADR-0031 Phase B (Block B2c): resume from a tournament-wide pause.
  Future<void> resume(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).resumeTournament(id);
    _invalidateScheduleControlOverview();
  }

  /// ADR-0031 Phase B (Block B2c): skip the active round's call/break window
  /// forward (the round starts running now).
  Future<void> skipForward(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).skipScheduleForward(id);
    _invalidateScheduleControlOverview();
  }

  /// ADR-0031 Phase B (Block B2c): re-call the active round's window (OE-B4 —
  /// not a true rewind).
  Future<void> skipBack(TournamentId id) async {
    await _ref.read(tournamentRemoteProvider).skipScheduleBackward(id);
    _invalidateScheduleControlOverview();
  }

  /// Spec §6/§9.5: lengthen the live round by [seconds] (a positive amount).
  /// Pushes `tournament_adjust_round_time(+seconds)` via the port — the server
  /// writes only the schedule row, so the new time reaches the detail over the
  /// schedule CDC; no full schedule recompute. Refreshes the overview only
  /// (same seam rationale as the pause/resume/skip controls — see
  /// [_invalidateScheduleControlOverview]).
  Future<void> extendRound(TournamentId id, int seconds) async {
    await _ref.read(tournamentRemoteProvider).adjustRoundTime(id, seconds);
    _invalidateScheduleControlOverview();
  }

  /// Spec §6/§9.5: shorten the live round by [seconds] (a positive amount).
  /// Pushes `tournament_adjust_round_time(-seconds)`; the server clamps the
  /// result to >= 0. CDC-push, no recompute. Refreshes the overview only.
  Future<void> shortenRound(TournamentId id, int seconds) async {
    await _ref.read(tournamentRemoteProvider).adjustRoundTime(id, -seconds);
    _invalidateScheduleControlOverview();
  }

  /// Refresh after a pause/resume/skip control action (ADR-0031 Block B2c).
  ///
  /// Only [administrableTournamentsProvider] is invalidated: the dashboard
  /// overview is a plain `FutureProvider` with NO single-column CDC scope
  /// (OE-B3), so it cannot self-refresh and must be re-read to pick up the
  /// new schedule status / remaining seconds.
  ///
  /// The detail schedule is deliberately NOT invalidated. The B2s RPCs write
  /// only `tournament_round_schedule`, which is in the realtime publication,
  /// so the schedule CDC pushes the change for free ("Realtime gratis"). The
  /// detail seam is the CDC-stream-fold `tournamentRoundScheduleProvider`,
  /// whose doc-block in `tournament_realtime_provider.dart` (the
  /// `tournamentRoundScheduleRealtimeProvider` comment) warns that a naive
  /// `ref.invalidate` on it would RESET the accumulated round fold. We
  /// respect that seam and let the CDC push reach the detail instead.
  void _invalidateScheduleControlOverview() {
    _ref.invalidate(administrableTournamentsProvider);
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

  /// ADR-0039 §3 / ADR-0036: pairs the next Schoch/Swiss round of [stageNodeId].
  ///
  /// The CLIENT does the pairing in Dart — never the server. It reads the
  /// stage-scoped match list, folds the finished matches of THIS stage into the
  /// `SwissSystemStrategy` state (roster + prior results), computes the next
  /// round via [SwissSystemStrategy.planRound], and submits the result to
  /// `tournament_pair_round` (which only validates / materialises). Matches of
  /// other stages and classic (null-stage) matches are filtered out so the
  /// roster, the standings and the round number stay stage-scoped.
  ///
  /// The roster is the participants seen in [stageNodeId]'s matches in
  /// first-seen order — that order is the stable start number `planRound` uses
  /// as its final tiebreak (spec §6.1). Schoch byes count as a full win
  /// (`schochByeScore`, spec §4.2). After the submit the stage match list +
  /// detail are invalidated so the freshly paired round shows up.
  Future<void> pairRound(TournamentId tournamentId, String stageNodeId) async {
    final remote = _ref.read(tournamentRemoteProvider);
    final stageMatches = [
      for (final m in await remote.listMatchesForTournament(tournamentId))
        if (m.stageNodeId == stageNodeId) m,
    ];

    final roster = <String>[];
    var lastRound = 0;
    final completed = <MatchResult>[];
    for (final m in stageMatches) {
      final a = m.participantA?.value;
      if (a != null && !roster.contains(a)) roster.add(a);
      final b = m.participantB?.value;
      if (b != null && !roster.contains(b)) roster.add(b);
      if (m.roundNumber > lastRound) lastRound = m.roundNumber;
      if (!_isStandingsCounted(m)) continue;
      completed.add(
        MatchResult(
          participantA: a!,
          participantB: b,
          pointsA: b == null ? schochByeScore : (m.finalScoreA ?? 0),
          pointsB: m.finalScoreB ?? 0,
          roundNumber: m.roundNumber,
        ),
      );
    }

    final planned = const SwissSystemStrategy().planRound(
      participants: roster,
      completedMatches: completed,
      roundNumber: lastRound + 1,
      tournamentId: tournamentId.value,
    );

    await remote.pairStageRound(
      tournamentId: tournamentId,
      stageNodeId: stageNodeId,
      pairings: planned.pairings,
    );
    _ref
      ..invalidate(tournamentMatchListProvider(tournamentId))
      ..invalidate(tournamentDetailProvider(tournamentId));
  }

  bool _isStandingsCounted(TournamentMatchRef m) =>
      m.status == TournamentMatchStatus.finalized ||
      m.status == TournamentMatchStatus.overridden;
}
