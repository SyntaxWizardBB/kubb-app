import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/club/application/club_providers.dart';
import 'package:kubb_app/features/club/data/club_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:logging/logging.dart';

/// Error detail attached to a [ClubActionFailure]. Mirrors the team feature's
/// result type so screens can pattern-match instead of inspecting nullables.
sealed class ClubActionError {
  const ClubActionError({required this.rpc});
  final String rpc;
}

class ClubActionExceptionError extends ClubActionError {
  const ClubActionExceptionError({
    required super.rpc,
    required this.error,
    required this.stackTrace,
  });
  final Object error;
  final StackTrace stackTrace;
}

class ClubActionNullReturnError extends ClubActionError {
  const ClubActionNullReturnError({required super.rpc});
}

sealed class ClubActionResult<T> {
  const ClubActionResult();
}

class ClubActionSuccess<T> extends ClubActionResult<T> {
  const ClubActionSuccess(this.value);
  final T value;
}

class ClubActionFailure<T> extends ClubActionResult<T> {
  const ClubActionFailure(this.error);
  final ClubActionError error;
}

final _log = Logger('club.membership');

/// Imperative write surface for the club feature. Reads flow through
/// [clubListProvider] / [clubDetailProvider]; this notifier owns every write
/// and the provider invalidation that follows.
class ClubMembershipController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue<void>.data(null);

  ClubRepository get _repo => ref.read(clubRepositoryProvider);

  Future<ClubActionResult<ClubId>> create({required String displayName}) {
    return _runReturning<ClubId>(
      rpc: 'club_create',
      action: () async {
        final id = await _repo.createClub(displayName: displayName);
        ref.invalidate(clubListProvider);
        return id;
      },
    );
  }

  Future<ClubActionResult<ClubInvitationId>> invite(
    ClubId clubId,
    UserId inviteeUserId,
  ) {
    return _runReturning<ClubInvitationId>(
      rpc: 'club_invite',
      action: () async {
        final id = await _repo.invite(clubId, inviteeUserId);
        ref.invalidate(clubDetailProvider(clubId));
        return id;
      },
    );
  }

  Future<void> respondInvitation(
    ClubInvitationId invitationId, {
    required bool accept,
  }) {
    return _run(
      rpc: 'club_invitation_respond',
      action: () async {
        await _repo.respondInvitation(invitationId, accept: accept);
        ref.invalidate(clubListProvider);
      },
    );
  }

  Future<void> setRoles(
    ClubId clubId,
    UserId memberUserId,
    List<String> roles,
  ) {
    return _run(
      rpc: 'club_set_member_roles',
      action: () async {
        await _repo.setMemberRoles(clubId, memberUserId, roles);
        ref.invalidate(clubDetailProvider(clubId));
      },
    );
  }

  Future<void> removeMember(ClubId clubId, UserId memberUserId) {
    return _run(
      rpc: 'club_remove_member',
      action: () async {
        await _repo.removeMember(clubId, memberUserId);
        ref.invalidate(clubDetailProvider(clubId));
      },
    );
  }

  Future<void> leave(ClubId clubId) {
    return _run(
      rpc: 'club_leave',
      action: () async {
        await _repo.leave(clubId);
        ref
          ..invalidate(clubDetailProvider(clubId))
          ..invalidate(clubListProvider);
      },
    );
  }

  Future<void> requestJoin(ClubId clubId) {
    return _run(
      rpc: 'club_request_join',
      action: () => _repo.requestJoin(clubId),
    );
  }

  Future<void> respondJoinRequest(
    ClubId clubId,
    String requestId, {
    required bool accept,
  }) {
    return _run(
      rpc: 'club_respond_join_request',
      action: () async {
        await _repo.respondJoinRequest(requestId, accept: accept);
        ref
          ..invalidate(clubJoinRequestsProvider(clubId))
          ..invalidate(clubDetailProvider(clubId));
      },
    );
  }

  Future<ClubActionResult<T>> _runReturning<T extends Object>({
    required String rpc,
    required Future<T?> Function() action,
  }) async {
    if (state.isLoading) {
      return ClubActionFailure<T>(ClubActionNullReturnError(rpc: rpc));
    }
    state = const AsyncValue<void>.loading();
    try {
      final value = await action();
      state = const AsyncValue<void>.data(null);
      if (value == null) {
        _log.warning('club action returned null', 'rpc=$rpc');
        return ClubActionFailure<T>(ClubActionNullReturnError(rpc: rpc));
      }
      return ClubActionSuccess<T>(value);
    } on Object catch (error, stackTrace) {
      _log.warning('club action failed', 'rpc=$rpc', stackTrace);
      state = AsyncValue<void>.error(error, stackTrace);
      return ClubActionFailure<T>(
        ClubActionExceptionError(
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

final clubMembershipControllerProvider =
    NotifierProvider<ClubMembershipController, AsyncValue<void>>(
  ClubMembershipController.new,
);
