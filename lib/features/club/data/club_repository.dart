import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/club/data/club_models.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The caller lacks authentication or club-management rights (SQLSTATE 42501).
class ClubPermissionException implements Exception {
  const ClubPermissionException(this.message);
  final String message;
  @override
  String toString() => 'ClubPermissionException: $message';
}

/// The founding code did not match the global code.
class ClubInvalidCodeException implements Exception {
  const ClubInvalidCodeException();
  @override
  String toString() => 'ClubInvalidCodeException';
}

/// A pending invitation already exists for that invitee.
class ClubInvitationDuplicateException implements Exception {
  const ClubInvitationDuplicateException(this.message);
  final String message;
  @override
  String toString() => 'ClubInvitationDuplicateException: $message';
}

/// The nickname did not resolve to a known player.
class ClubUserNotFoundException implements Exception {
  const ClubUserNotFoundException();
  @override
  String toString() => 'ClubUserNotFoundException';
}

/// Catch-all for the remaining token-prefixed club RPC errors.
class ClubOperationException implements Exception {
  const ClubOperationException(this.message);
  final String message;
  @override
  String toString() => 'ClubOperationException: $message';
}

/// Data access for the club (Verein) feature. All writes go through the
/// SECURITY DEFINER RPCs in migration 20260901000013; reads use
/// `club_list_for_caller` / `club_get`. Error mapping and the expired-JWT
/// self-heal mirror [team feature]'s repository.
class ClubRepository {
  ClubRepository({
    required SupabaseClient client,
    Future<WireSessionOutcome> Function()? reSignWireSession,
  })  : _client = client,
        _reSignWireSession = reSignWireSession;

  final SupabaseClient _client;
  final Future<WireSessionOutcome> Function()? _reSignWireSession;

  /// Founds a club. Returns null only if the RPC succeeds yet yields no id
  /// (treated as a recoverable failure upstream). Throws
  /// [ClubInvalidCodeException] when the code is wrong.
  Future<ClubId?> createClub({required String displayName}) async {
    // Founding is gated server-side on the profile's can_found_clubs flag
    // (set from the early-access organizer code) — no per-create code anymore.
    final id = await _guard(() => _client.rpc<String?>(
          'club_create',
          params: <String, dynamic>{'p_display_name': displayName},
        ));
    return id == null ? null : ClubId(id);
  }

  Future<List<ClubWire>> listMyClubs() async {
    final rows = await _guard(
      () => _client.rpc<List<dynamic>>('club_list_for_caller'),
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(ClubWire.fromJson)
        .toList(growable: false);
  }

  Future<ClubDetail> getClub(ClubId id) async {
    final json = await _guard(() => _client.rpc<Map<String, dynamic>>(
          'club_get',
          params: <String, dynamic>{'p_club_id': id.value},
        ));
    return ClubDetail.fromJson(json);
  }

  /// Invites a player by user id — the search-based path (mirrors team add).
  Future<ClubInvitationId?> invite(ClubId clubId, UserId inviteeUserId) async {
    final id = await _guard(() => _client.rpc<String?>(
          'club_invite',
          params: <String, dynamic>{
            'p_club_id': clubId.value,
            'p_invitee_user_id': inviteeUserId.value,
          },
        ));
    return id == null ? null : ClubInvitationId(id);
  }

  Future<ClubInvitationId?> inviteByNickname(
    ClubId clubId,
    String nickname,
  ) async {
    final id = await _guard(() => _client.rpc<String?>(
          'club_invite_by_nickname',
          params: <String, dynamic>{
            'p_club_id': clubId.value,
            'p_nickname': nickname,
          },
        ));
    return id == null ? null : ClubInvitationId(id);
  }

  Future<void> respondInvitation(
    ClubInvitationId invitationId, {
    required bool accept,
  }) async {
    await _guard(() => _client.rpc<void>(
          'club_invitation_respond',
          params: <String, dynamic>{
            'p_invitation_id': invitationId.value,
            'p_accept': accept,
          },
        ));
  }

  Future<void> setMemberRoles(
    ClubId clubId,
    UserId memberUserId,
    List<String> roles,
  ) async {
    await _guard(() => _client.rpc<void>(
          'club_set_member_roles',
          params: <String, dynamic>{
            'p_club_id': clubId.value,
            'p_member_user_id': memberUserId.value,
            'p_roles': roles,
          },
        ));
  }

  Future<void> removeMember(ClubId clubId, UserId memberUserId) async {
    await _guard(() => _client.rpc<void>(
          'club_remove_member',
          params: <String, dynamic>{
            'p_club_id': clubId.value,
            'p_member_user_id': memberUserId.value,
          },
        ));
  }

  Future<void> leave(ClubId clubId) async {
    await _guard(() => _client.rpc<void>(
          'club_leave',
          params: <String, dynamic>{'p_club_id': clubId.value},
        ));
  }

  Future<void> requestJoin(ClubId clubId) async {
    await _guard(() => _client.rpc<void>(
          'club_request_join',
          params: <String, dynamic>{'p_club_id': clubId.value},
        ));
  }

  Future<List<ClubJoinRequestWire>> listJoinRequests(ClubId clubId) async {
    final out = await _guard(() => _client.rpc<List<dynamic>>(
          'club_list_join_requests',
          params: <String, dynamic>{'p_club_id': clubId.value},
        ));
    return out
        .cast<Map<String, dynamic>>()
        .map(ClubJoinRequestWire.fromJson)
        .toList(growable: false);
  }

  Future<void> respondJoinRequest(
    String requestId, {
    required bool accept,
  }) async {
    await _guard(() => _client.rpc<void>(
          'club_respond_join_request',
          params: <String, dynamic>{
            'p_request_id': requestId,
            'p_accept': accept,
          },
        ));
  }

  Future<bool> callerCanPublish() async {
    final result = await _guard(
      () => _client.rpc<bool>('club_caller_can_publish'),
    );
    return result;
  }

  /// Searches public clubs by name prefix/substring for the join flow. Reads
  /// the `clubs` table directly (public-read RLS); excludes dissolved clubs.
  Future<List<ClubWire>> searchClubs(String query) async {
    final rows = await _guard(() => _client
        .from('clubs')
        .select()
        .isFilter('dissolved_at', null)
        .ilike('display_name', '%$query%')
        .order('display_name')
        .limit(30));
    return rows
        .cast<Map<String, dynamic>>()
        .map(ClubWire.fromJson)
        .toList(growable: false);
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on PostgrestException catch (e) {
      // Self-heal an expired Phase-1 keypair JWT (PGRST303) once, mirroring
      // the team repository.
      if (_isExpiredJwt(e) && _reSignWireSession != null) {
        final outcome = await _reSignWireSession();
        if (outcome == WireSessionOutcome.keypairResigned ||
            outcome == WireSessionOutcome.oauthRefreshed ||
            outcome == WireSessionOutcome.alreadyLive) {
          try {
            return await run();
          } on PostgrestException catch (retryError) {
            throw _mapException(retryError);
          }
        }
      }
      throw _mapException(e);
    }
  }

  static bool _isExpiredJwt(PostgrestException e) =>
      e.code == 'PGRST303' || e.message.contains('JWT expired');

  Exception _mapException(PostgrestException e) {
    if (e.code == '42501') {
      return ClubPermissionException(e.message);
    }
    final message = e.message;
    if (message.startsWith('INVALID_FOUNDING_CODE')) {
      return const ClubInvalidCodeException();
    }
    if (message.startsWith('USER_NOT_FOUND')) {
      return const ClubUserNotFoundException();
    }
    if (message.startsWith('INVITATION_ALREADY_PENDING')) {
      return ClubInvitationDuplicateException(message);
    }
    return ClubOperationException(message);
  }
}

final clubRepositoryProvider = Provider<ClubRepository>((ref) {
  return ClubRepository(
    client: Supabase.instance.client,
    reSignWireSession: () => ensureWireSession(ref, force: true),
  );
});
