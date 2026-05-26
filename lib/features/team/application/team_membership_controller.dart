import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/team/application/team_detail_provider.dart';
import 'package:kubb_app/features/team/application/team_list_provider.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Imperative action surface for the team feature. Screens read teams
/// via [teamListProvider] and [teamDetailProvider]; this notifier owns
/// every write so the FutureProvider invalidation pattern lives in
/// exactly one place (TASK-M3.1-T9 contract).
///
/// [state] tracks the in-flight async lifecycle of the *last*
/// triggered action so the screens can disable buttons and surface
/// errors without re-implementing try/catch plumbing. Each method
/// guards against re-entry while loading and invalidates the affected
/// list / detail providers on success.
class TeamMembershipController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue<void>.data(null);

  /// Creates a fresh team. On success the calling user becomes the
  /// sole pool member and the team list refreshes.
  Future<TeamId?> create({
    required String displayName,
    required LeagueMembership leagueMembership,
    String? logoUrl,
    String? country,
  }) {
    return _runReturning(() async {
      final id = await _repo.createTeam(
        displayName: displayName,
        leagueMembership: leagueMembership,
        logoUrl: logoUrl,
        country: country,
      );
      ref.invalidate(teamListProvider);
      return id;
    });
  }

  /// Sends an invitation to [inviteeUserId] for joining [teamId].
  Future<TeamInvitationId?> invite(TeamId teamId, UserId inviteeUserId) {
    return _runReturning(() async {
      final id = await _repo.invite(teamId, inviteeUserId);
      ref.invalidate(teamDetailProvider(teamId));
      return id;
    });
  }

  /// Accepts or declines an inbox invitation. When accepted the new
  /// team shows up in "Meine Teams" after the list refetches.
  Future<void> respondInvitation(
    TeamInvitationId invitationId, {
    required bool accept,
  }) {
    return _run(() async {
      await _repo.respondInvitation(invitationId, accept: accept);
      if (accept) ref.invalidate(teamListProvider);
    });
  }

  /// Registers an unregistered guest player as part of [teamId]'s
  /// pool. Guests only exist as roster fillers — they cannot
  /// authenticate or be invited again.
  Future<TeamGuestPlayerId?> addGuest(TeamId teamId, String displayName) {
    return _runReturning(() async {
      final id = await _repo.addGuest(teamId, displayName);
      ref.invalidate(teamDetailProvider(teamId));
      return id;
    });
  }

  /// Removes a registered pool member. The server emits the OD-M3-01
  /// inbox notifications to all other pool members.
  Future<void> removeMember(TeamId teamId, UserId memberUserId) {
    return _run(() async {
      await _repo.removeMember(teamId, memberUserId);
      ref
        ..invalidate(teamDetailProvider(teamId))
        ..invalidate(teamListProvider);
    });
  }

  /// Removes a guest player from the pool.
  Future<void> removeGuest(TeamId teamId, TeamGuestPlayerId guestPlayerId) {
    return _run(() async {
      await _repo.removeGuest(teamId, guestPlayerId);
      ref.invalidate(teamDetailProvider(teamId));
    });
  }

  /// Caller leaves [teamId]. Triggers FR-TEAM-19 auto-dissolve on the
  /// server when the caller was the last registered member.
  Future<void> leave(TeamId teamId) {
    return _run(() async {
      await _repo.leave(teamId);
      ref
        ..invalidate(teamListProvider)
        ..invalidate(teamDetailProvider(teamId));
    });
  }

  /// Dissolves [teamId]. Requires every active pool member to have
  /// emitted a prior consent event — the repository raises
  /// [TeamDissolveNeedsConsentException] otherwise.
  Future<void> dissolve(TeamId teamId) {
    return _run(() async {
      await _repo.dissolve(teamId);
      ref
        ..invalidate(teamListProvider)
        ..invalidate(teamDetailProvider(teamId));
    });
  }

  TeamRepository get _repo => ref.read(teamRepositoryProvider);

  /// Runs a void-returning action under the standard guard: re-entry
  /// blocked while loading, errors captured into [state].
  Future<void> _run(Future<void> Function() action) async {
    if (state.isLoading) return;
    state = const AsyncValue<void>.loading();
    state = await AsyncValue.guard(action);
  }

  /// Variant for actions that return an id (typically used for
  /// post-success navigation). `null` is yielded when the action threw
  /// — the error itself is exposed via [state].
  Future<T?> _runReturning<T>(Future<T> Function() action) async {
    if (state.isLoading) return null;
    state = const AsyncValue<void>.loading();
    T? result;
    state = await AsyncValue.guard(() async {
      result = await action();
    });
    return state.hasError ? null : result;
  }
}

/// Singleton controller — there is at most one team-mutation in
/// flight per app session and the screens want to share its error
/// state across the detail and list surfaces.
final teamMembershipControllerProvider =
    NotifierProvider<TeamMembershipController, AsyncValue<void>>(
  TeamMembershipController.new,
);
