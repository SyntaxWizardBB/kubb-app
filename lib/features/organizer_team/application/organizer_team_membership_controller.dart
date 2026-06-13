import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/organizer_team/application/organizer_team_providers.dart';
import 'package:kubb_app/features/organizer_team/data/organizer_team_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:logging/logging.dart';

/// Error detail attached to a [OrganizerTeamActionFailure]. Mirrors the team feature's
/// result type so screens can pattern-match instead of inspecting nullables.
sealed class OrganizerTeamActionError {
  const OrganizerTeamActionError({required this.rpc});
  final String rpc;
}

class OrganizerTeamActionExceptionError extends OrganizerTeamActionError {
  const OrganizerTeamActionExceptionError({
    required super.rpc,
    required this.error,
    required this.stackTrace,
  });
  final Object error;
  final StackTrace stackTrace;
}

class OrganizerTeamActionNullReturnError extends OrganizerTeamActionError {
  const OrganizerTeamActionNullReturnError({required super.rpc});
}

sealed class OrganizerTeamActionResult<T> {
  const OrganizerTeamActionResult();
}

class OrganizerTeamActionSuccess<T> extends OrganizerTeamActionResult<T> {
  const OrganizerTeamActionSuccess(this.value);
  final T value;
}

class OrganizerTeamActionFailure<T> extends OrganizerTeamActionResult<T> {
  const OrganizerTeamActionFailure(this.error);
  final OrganizerTeamActionError error;
}

final _log = Logger('club.membership');

/// Imperative write surface for the club feature. Reads flow through
/// [organizerTeamListProvider] / [organizerTeamDetailProvider]; this notifier owns every write
/// and the provider invalidation that follows.
class OrganizerTeamMembershipController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue<void>.data(null);

  OrganizerTeamRepository get _repo => ref.read(organizerTeamRepositoryProvider);

  Future<OrganizerTeamActionResult<OrganizerTeamId>> create({required String displayName}) {
    return _runReturning<OrganizerTeamId>(
      rpc: 'organizer_team_create',
      action: () async {
        final id = await _repo.createClub(displayName: displayName);
        ref.invalidate(organizerTeamListProvider);
        return id;
      },
    );
  }

  /// [role] is the club role granted when the invitee accepts
  /// (owner/admin/referee, validated server-side).
  Future<OrganizerTeamActionResult<OrganizerTeamInvitationId>> invite(
    OrganizerTeamId clubId,
    UserId inviteeUserId, {
    String role = 'admin',
  }) {
    return _runReturning<OrganizerTeamInvitationId>(
      rpc: 'organizer_team_invite',
      action: () async {
        final id = await _repo.invite(clubId, inviteeUserId, role: role);
        ref.invalidate(organizerTeamDetailProvider(clubId));
        return id;
      },
    );
  }

  Future<void> respondInvitation(
    OrganizerTeamInvitationId invitationId, {
    required bool accept,
  }) {
    return _run(
      rpc: 'organizer_team_invitation_respond',
      action: () async {
        await _repo.respondInvitation(invitationId, accept: accept);
        ref.invalidate(organizerTeamListProvider);
      },
    );
  }

  Future<void> setRoles(
    OrganizerTeamId clubId,
    UserId memberUserId,
    List<String> roles,
  ) {
    return _run(
      rpc: 'organizer_team_set_member_roles',
      action: () async {
        await _repo.setMemberRoles(clubId, memberUserId, roles);
        ref.invalidate(organizerTeamDetailProvider(clubId));
      },
    );
  }

  Future<void> removeMember(OrganizerTeamId clubId, UserId memberUserId) {
    return _run(
      rpc: 'organizer_team_remove_member',
      action: () async {
        await _repo.removeMember(clubId, memberUserId);
        ref.invalidate(organizerTeamDetailProvider(clubId));
      },
    );
  }

  Future<void> leave(OrganizerTeamId clubId) {
    return _run(
      rpc: 'organizer_team_leave',
      action: () async {
        await _repo.leave(clubId);
        ref
          ..invalidate(organizerTeamDetailProvider(clubId))
          ..invalidate(organizerTeamListProvider);
      },
    );
  }

  Future<void> requestJoin(OrganizerTeamId clubId) {
    return _run(
      rpc: 'organizer_team_request_join',
      action: () => _repo.requestJoin(clubId),
    );
  }

  Future<void> respondJoinRequest(
    OrganizerTeamId clubId,
    String requestId, {
    required bool accept,
  }) {
    return _run(
      rpc: 'organizer_team_respond_join_request',
      action: () async {
        await _repo.respondJoinRequest(requestId, accept: accept);
        ref
          ..invalidate(organizerTeamJoinRequestsProvider(clubId))
          ..invalidate(organizerTeamDetailProvider(clubId));
      },
    );
  }

  Future<OrganizerTeamActionResult<T>> _runReturning<T extends Object>({
    required String rpc,
    required Future<T?> Function() action,
  }) async {
    if (state.isLoading) {
      return OrganizerTeamActionFailure<T>(OrganizerTeamActionNullReturnError(rpc: rpc));
    }
    state = const AsyncValue<void>.loading();
    try {
      final value = await action();
      state = const AsyncValue<void>.data(null);
      if (value == null) {
        _log.warning('club action returned null', 'rpc=$rpc');
        return OrganizerTeamActionFailure<T>(OrganizerTeamActionNullReturnError(rpc: rpc));
      }
      return OrganizerTeamActionSuccess<T>(value);
    } on Object catch (error, stackTrace) {
      _log.warning('club action failed', 'rpc=$rpc', stackTrace);
      state = AsyncValue<void>.error(error, stackTrace);
      return OrganizerTeamActionFailure<T>(
        OrganizerTeamActionExceptionError(
          rpc: rpc,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<void> _run({
    required String rpc,
    required Future<void> Function() action,
  }) async {
    state = const AsyncValue<void>.loading();
    state = await AsyncValue.guard(action);
    if (state.hasError) {
      _log.warning('club action failed', 'rpc=$rpc', state.stackTrace);
    }
  }
}

final organizerTeamMembershipControllerProvider =
    NotifierProvider<OrganizerTeamMembershipController, AsyncValue<void>>(
  OrganizerTeamMembershipController.new,
);
