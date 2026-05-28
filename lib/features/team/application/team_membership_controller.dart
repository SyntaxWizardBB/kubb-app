import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/team/application/team_detail_provider.dart';
import 'package:kubb_app/features/team/application/team_list_provider.dart';
import 'package:kubb_app/features/team/application/team_providers.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:logging/logging.dart';

/// Sealed error type for the imperative team actions exposed by
/// [TeamMembershipController]. Lets callers distinguish a thrown
/// repository error from the silent "RPC succeeded but returned null"
/// path that the team_create RPC can produce when an internal
/// constraint trips without surfacing as a PostgrestException.
sealed class TeamActionError {
  const TeamActionError({required this.rpc});

  /// Short, PII-free identifier of the RPC the action wrapped
  /// (e.g. `team_create`). Safe to embed in logs and telemetry.
  final String rpc;
}

/// The repository threw — typically a [TeamPermissionException],
/// [TeamOperationException], or a transport-level error.
class TeamActionExceptionError extends TeamActionError {
  const TeamActionExceptionError({
    required super.rpc,
    required this.error,
    required this.stackTrace,
  });

  final Object error;
  final StackTrace stackTrace;
}

/// The RPC returned `null` without raising. The team feature treats
/// this as a recoverable failure: surface a snackbar, keep the form
/// enabled, do not throw.
class TeamActionNullReturnError extends TeamActionError {
  const TeamActionNullReturnError({required super.rpc});
}

/// Sealed result for [TeamMembershipController] actions that yield a
/// value. Callers pattern-match to drive navigation vs. error UX
/// instead of inspecting a nullable id.
sealed class TeamActionResult<T> {
  const TeamActionResult();
}

class TeamActionSuccess<T> extends TeamActionResult<T> {
  const TeamActionSuccess(this.value);
  final T value;
}

class TeamActionFailure<T> extends TeamActionResult<T> {
  const TeamActionFailure(this.error);
  final TeamActionError error;
}

final _log = Logger('team.membership');

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
  Future<TeamActionResult<TeamId>> create({
    required String displayName,
    required LeagueMembership leagueMembership,
    String? logoUrl,
    String? country,
  }) {
    return _runReturning<TeamId>(
      rpc: 'team_create',
      action: () async {
        final id = await _repo.createTeam(
          displayName: displayName,
          leagueMembership: leagueMembership,
          logoUrl: logoUrl,
          country: country,
        );
        ref.invalidate(teamListProvider);
        return id;
      },
    );
  }

  /// Sends an invitation to [inviteeUserId] for joining [teamId].
  Future<TeamActionResult<TeamInvitationId>> invite(
    TeamId teamId,
    UserId inviteeUserId,
  ) {
    return _runReturning<TeamInvitationId>(
      rpc: 'team_invite',
      action: () async {
        final id = await _repo.invite(teamId, inviteeUserId);
        ref.invalidate(teamDetailProvider(teamId));
        return id;
      },
    );
  }

  /// Accepts or declines an inbox invitation. When accepted the new
  /// team shows up in "Meine Teams" after the list refetches.
  ///
  /// [teamId] is optional because the inbox row historically carried
  /// only the invitation id. When the caller can supply it (e.g. the
  /// invitation screen reads it from the joined `teams!inner` row), the
  /// per-team detail cache is invalidated as well so the new pool
  /// roster surfaces without a manual pull-to-refresh (R19-F-17).
  Future<void> respondInvitation(
    TeamInvitationId invitationId, {
    required bool accept,
    TeamId? teamId,
  }) {
    return _run(() async {
      await _repo.respondInvitation(invitationId, accept: accept);
      ref.invalidate(pendingInvitationsProvider);
      if (accept) {
        ref.invalidate(teamListProvider);
        if (teamId != null) ref.invalidate(teamDetailProvider(teamId));
      }
    });
  }

  /// Registers an unregistered guest player as part of [teamId]'s
  /// pool. Guests only exist as roster fillers — they cannot
  /// authenticate or be invited again.
  Future<TeamActionResult<TeamGuestPlayerId>> addGuest(
    TeamId teamId,
    String displayName,
  ) {
    return _runReturning<TeamGuestPlayerId>(
      rpc: 'team_add_guest',
      action: () async {
        final id = await _repo.addGuest(teamId, displayName);
        ref.invalidate(teamDetailProvider(teamId));
        return id;
      },
    );
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

  /// Runs an id-returning action and folds the outcome into a
  /// [TeamActionResult]. A thrown error becomes
  /// [TeamActionExceptionError]; a `null` return from the action
  /// (RPC succeeded but produced no id) becomes
  /// [TeamActionNullReturnError]. Both failure paths emit a
  /// `Logger('team.membership').warning(...)` entry carrying only the
  /// RPC name — no team / user identifiers, no display names, no
  /// email addresses.
  Future<TeamActionResult<T>> _runReturning<T extends Object>({
    required String rpc,
    required Future<T?> Function() action,
  }) async {
    if (state.isLoading) {
      return TeamActionFailure<T>(TeamActionNullReturnError(rpc: rpc));
    }
    state = const AsyncValue<void>.loading();
    try {
      final value = await action();
      if (value == null) {
        _log.warning('team action returned null', 'rpc=$rpc');
        state = const AsyncValue<void>.data(null);
        return TeamActionFailure<T>(TeamActionNullReturnError(rpc: rpc));
      }
      state = const AsyncValue<void>.data(null);
      return TeamActionSuccess<T>(value);
    } on Object catch (error, stackTrace) {
      _log.warning('team action failed', 'rpc=$rpc', stackTrace);
      state = AsyncValue<void>.error(error, stackTrace);
      return TeamActionFailure<T>(
        TeamActionExceptionError(
          rpc: rpc,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

/// Singleton controller — there is at most one team-mutation in
/// flight per app session and the screens want to share its error
/// state across the detail and list surfaces.
final teamMembershipControllerProvider =
    NotifierProvider<TeamMembershipController, AsyncValue<void>>(
  TeamMembershipController.new,
);
