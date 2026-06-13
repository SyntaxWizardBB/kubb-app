import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/organizer_team/data/organizer_team_models.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The caller lacks authentication or club-management rights (SQLSTATE 42501).
class OrganizerTeamPermissionException implements Exception {
  const OrganizerTeamPermissionException(this.message);
  final String message;
  @override
  String toString() => 'OrganizerTeamPermissionException: $message';
}

/// The founding code did not match the global code.
class OrganizerTeamInvalidCodeException implements Exception {
  const OrganizerTeamInvalidCodeException();
  @override
  String toString() => 'OrganizerTeamInvalidCodeException';
}

/// A pending invitation already exists for that invitee.
class OrganizerTeamInvitationDuplicateException implements Exception {
  const OrganizerTeamInvitationDuplicateException(this.message);
  final String message;
  @override
  String toString() => 'OrganizerTeamInvitationDuplicateException: $message';
}

/// The nickname did not resolve to a known player.
class OrganizerTeamUserNotFoundException implements Exception {
  const OrganizerTeamUserNotFoundException();
  @override
  String toString() => 'OrganizerTeamUserNotFoundException';
}

/// Raised when `organizer_team_create` rejects the chosen name because another club
/// already carries it (server SQLSTATE 23505, backed by
/// `clubs_display_name_unique_idx`). Lets the UI show a clear "name taken"
/// message even when the optimistic live availability check raced.
class OrganizerTeamDuplicateNameException implements Exception {
  const OrganizerTeamDuplicateNameException();
  @override
  String toString() => 'OrganizerTeamDuplicateNameException';
}

/// Catch-all for the remaining token-prefixed club RPC errors.
class OrganizerTeamOperationException implements Exception {
  const OrganizerTeamOperationException(this.message);
  final String message;
  @override
  String toString() => 'OrganizerTeamOperationException: $message';
}

/// Data access for the club (Verein) feature. All writes go through the
/// SECURITY DEFINER RPCs in migration 20260901000013; reads use
/// `organizer_team_list_for_caller` / `organizer_team_get`. Error mapping and the expired-JWT
/// self-heal mirror [team feature]'s repository.
class OrganizerTeamRepository {
  OrganizerTeamRepository({
    required SupabaseClient client,
    Future<WireSessionOutcome> Function()? reSignWireSession,
  })  : _client = client,
        _reSignWireSession = reSignWireSession;

  final SupabaseClient _client;
  final Future<WireSessionOutcome> Function()? _reSignWireSession;

  /// Founds a club. Returns null only if the RPC succeeds yet yields no id
  /// (treated as a recoverable failure upstream). Throws
  /// [OrganizerTeamInvalidCodeException] when the code is wrong.
  Future<OrganizerTeamId?> createClub({required String displayName}) async {
    // Founding is gated server-side on the profile's can_found_clubs flag
    // (set from the early-access organizer code) — no per-create code anymore.
    final id = await _guard(() => _client.rpc<String?>(
          'organizer_team_create',
          params: <String, dynamic>{'p_display_name': displayName},
        ));
    return id == null ? null : OrganizerTeamId(id);
  }

  /// Whether [displayName] is free for a club. Case- and whitespace-
  /// insensitive; pass [excludeClubId] for a future rename so the club's own
  /// current name is not flagged. Returns false for blank input.
  Future<bool> isNameAvailable(String displayName, {OrganizerTeamId? excludeClubId}) {
    return _guard(() => _client.rpc<bool>(
          'organizer_team_name_available',
          params: <String, dynamic>{
            'p_display_name': displayName,
            'p_exclude_club_id': excludeClubId?.value,
          },
        ));
  }

  Future<List<OrganizerTeamWire>> listMyClubs() async {
    final rows = await _guard(
      () => _client.rpc<List<dynamic>>('organizer_team_list_for_caller'),
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(OrganizerTeamWire.fromJson)
        .toList(growable: false);
  }

  Future<OrganizerTeamDetail> getClub(OrganizerTeamId id) async {
    final json = await _guard(() => _client.rpc<Map<String, dynamic>>(
          'organizer_team_get',
          params: <String, dynamic>{'p_club_id': id.value},
        ));
    return OrganizerTeamDetail.fromJson(json);
  }

  /// Invites a player by user id — the search-based path (mirrors team add).
  /// [role] is the club role granted on accept (server CHECK:
  /// owner/admin/referee, migration 20261282000000).
  Future<OrganizerTeamInvitationId?> invite(
    OrganizerTeamId clubId,
    UserId inviteeUserId, {
    String role = 'admin',
  }) async {
    final id = await _guard(() => _client.rpc<String?>(
          'organizer_team_invite',
          params: <String, dynamic>{
            'p_club_id': clubId.value,
            'p_invitee_user_id': inviteeUserId.value,
            'p_role': role,
          },
        ));
    return id == null ? null : OrganizerTeamInvitationId(id);
  }

  Future<OrganizerTeamInvitationId?> inviteByNickname(
    OrganizerTeamId clubId,
    String nickname, {
    String role = 'admin',
  }) async {
    final id = await _guard(() => _client.rpc<String?>(
          'organizer_team_invite_by_nickname',
          params: <String, dynamic>{
            'p_club_id': clubId.value,
            'p_nickname': nickname,
            'p_role': role,
          },
        ));
    return id == null ? null : OrganizerTeamInvitationId(id);
  }

  Future<void> respondInvitation(
    OrganizerTeamInvitationId invitationId, {
    required bool accept,
  }) async {
    await _guard(() => _client.rpc<void>(
          'organizer_team_invitation_respond',
          params: <String, dynamic>{
            'p_invitation_id': invitationId.value,
            'p_accept': accept,
          },
        ));
  }

  Future<void> setMemberRoles(
    OrganizerTeamId clubId,
    UserId memberUserId,
    List<String> roles,
  ) async {
    await _guard(() => _client.rpc<void>(
          'organizer_team_set_member_roles',
          params: <String, dynamic>{
            'p_club_id': clubId.value,
            'p_member_user_id': memberUserId.value,
            'p_roles': roles,
          },
        ));
  }

  Future<void> removeMember(OrganizerTeamId clubId, UserId memberUserId) async {
    await _guard(() => _client.rpc<void>(
          'organizer_team_remove_member',
          params: <String, dynamic>{
            'p_club_id': clubId.value,
            'p_member_user_id': memberUserId.value,
          },
        ));
  }

  Future<void> leave(OrganizerTeamId clubId) async {
    await _guard(() => _client.rpc<void>(
          'organizer_team_leave',
          params: <String, dynamic>{'p_club_id': clubId.value},
        ));
  }

  Future<void> requestJoin(OrganizerTeamId clubId) async {
    await _guard(() => _client.rpc<void>(
          'organizer_team_request_join',
          params: <String, dynamic>{'p_club_id': clubId.value},
        ));
  }

  Future<List<OrganizerTeamJoinRequestWire>> listJoinRequests(OrganizerTeamId clubId) async {
    final out = await _guard(() => _client.rpc<List<dynamic>>(
          'organizer_team_list_join_requests',
          params: <String, dynamic>{'p_club_id': clubId.value},
        ));
    return out
        .cast<Map<String, dynamic>>()
        .map(OrganizerTeamJoinRequestWire.fromJson)
        .toList(growable: false);
  }

  Future<void> respondJoinRequest(
    String requestId, {
    required bool accept,
  }) async {
    await _guard(() => _client.rpc<void>(
          'organizer_team_respond_join_request',
          params: <String, dynamic>{
            'p_request_id': requestId,
            'p_accept': accept,
          },
        ));
  }

  Future<bool> callerCanPublish() async {
    final result = await _guard(
      () => _client.rpc<bool>('organizer_team_caller_can_publish'),
    );
    return result;
  }

  /// Whether the caller may act as an organizer (P4-C, ADR-0032 §4): true
  /// when the profile carries `can_found_clubs` OR any active club
  /// membership holds a role overlapping {owner, admin, referee}. Delegates
  /// entirely to the `organizer_team_caller_is_organizer` RPC (migration
  /// 20261282500000) — never decided client-side.
  Future<bool> callerIsOrganizer() async {
    final result = await _guard(
      () => _client.rpc<bool>('organizer_team_caller_is_organizer'),
    );
    return result;
  }

  /// Searches public organizer teams by name prefix/substring for the join
  /// flow. Reads the `organizer_teams` table directly (public-read RLS);
  /// excludes dissolved teams.
  Future<List<OrganizerTeamWire>> searchClubs(String query) async {
    final rows = await _guard(() => _client
        .from('organizer_teams')
        .select()
        .isFilter('dissolved_at', null)
        .ilike('display_name', '%$query%')
        .order('display_name')
        .limit(30));
    return rows
        .cast<Map<String, dynamic>>()
        .map(OrganizerTeamWire.fromJson)
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
      return OrganizerTeamPermissionException(e.message);
    }
    final message = e.message;
    // Unique club-name violation. The create guard raises 23505 with a
    // "a club named ... already exists" message; the bare
    // clubs_display_name_unique_idx also reports 23505 referencing that index.
    // Scope to those so the invite path's 23505 ("invitee already a member")
    // is NOT misclassified as a name conflict.
    if (e.code == '23505' &&
        (message.contains('club named') ||
            message.contains('clubs_display_name_unique_idx'))) {
      return const OrganizerTeamDuplicateNameException();
    }
    if (message.startsWith('INVALID_FOUNDING_CODE')) {
      return const OrganizerTeamInvalidCodeException();
    }
    if (message.startsWith('USER_NOT_FOUND')) {
      return const OrganizerTeamUserNotFoundException();
    }
    if (message.startsWith('INVITATION_ALREADY_PENDING')) {
      return OrganizerTeamInvitationDuplicateException(message);
    }
    return OrganizerTeamOperationException(message);
  }
}

final organizerTeamRepositoryProvider = Provider<OrganizerTeamRepository>((ref) {
  return OrganizerTeamRepository(
    client: Supabase.instance.client,
    reSignWireSession: () => ensureWireSession(ref, force: true),
  );
});
