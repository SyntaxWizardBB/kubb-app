import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/team/data/team_models.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Raised when the server rejected the call with `ERRCODE 42501`
/// (`insufficient_privilege`). The team RPCs use this both for the
/// unauthenticated path and for pool-membership guards.
class TeamPermissionException implements Exception {
  const TeamPermissionException(this.message);
  final String message;

  @override
  String toString() => 'TeamPermissionException: $message';
}

/// Raised when `team_invite` reports that a pending invitation for the
/// same `(team_id, invitee_user_id)` pair already exists. The server
/// emits the literal `INVITATION_ALREADY_PENDING` token as the message.
class TeamInvitationDuplicateException implements Exception {
  const TeamInvitationDuplicateException(this.message);
  final String message;

  @override
  String toString() => 'TeamInvitationDuplicateException: $message';
}

/// Raised when `team_dissolve` aborts because not every active pool
/// member has emitted a `dissolve_consent` audit event yet. The server
/// prefixes the message with `DISSOLVE_NEEDS_CONSENT:`.
class TeamDissolveNeedsConsentException implements Exception {
  const TeamDissolveNeedsConsentException(this.message);
  final String message;

  @override
  String toString() => 'TeamDissolveNeedsConsentException: $message';
}

/// Catch-all for the remaining token-prefixed errors the team RPCs
/// surface (`TARGET_NOT_MEMBER`, `TARGET_NOT_GUEST`, `TEAM_DISSOLVED`).
/// Callers can switch on [code] to render a localized message.
class TeamOperationException implements Exception {
  const TeamOperationException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'TeamOperationException($code): $message';
}

/// Wrapper around the ten `team_*` RPCs declared in migrations
/// `20260615000002_team_rpcs_a.sql` and `20260615000003_team_rpcs_b.sql`.
/// Every call is authenticated; the SECURITY DEFINER functions enforce
/// pool-membership rules and emit audit + inbox side-effects.
///
/// Per ADR-0002 the team feature is pragmatic CRUD and does not surface
/// a `TeamRemote` port — the repository hits Supabase directly and the
/// Riverpod providers (TASK-M3.1-T10) consume it.
class TeamRepository {
  TeamRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<TeamId> createTeam({
    required String displayName,
    required LeagueMembership leagueMembership,
    String? logoUrl,
    String? country,
  }) async {
    final id = await _guard(() => _client.rpc<String>(
          'team_create',
          params: <String, dynamic>{
            'p_display_name': displayName,
            'p_league_membership': leagueMembership.wire,
            'p_logo_url': logoUrl,
            'p_country': country,
          },
        ));
    return TeamId(id);
  }

  Future<List<TeamWire>> listMyTeams() async {
    final rows = await _guard(() => _client.rpc<List<dynamic>>(
          'team_list_for_caller',
        ));
    return rows
        .cast<Map<String, dynamic>>()
        .map(TeamWire.fromJson)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> getTeam(TeamId id) async {
    return _guard(() => _client.rpc<Map<String, dynamic>>(
          'team_get',
          params: <String, dynamic>{'p_team_id': id.value},
        ));
  }

  Future<TeamInvitationId> invite(TeamId teamId, UserId inviteeUserId) async {
    final id = await _guard(() => _client.rpc<String>(
          'team_invite',
          params: <String, dynamic>{
            'p_team_id': teamId.value,
            'p_invitee_user_id': inviteeUserId.value,
          },
        ));
    return TeamInvitationId(id);
  }

  Future<void> respondInvitation(
    TeamInvitationId invitationId, {
    required bool accept,
  }) {
    return _guard(() => _client.rpc<void>(
          'team_invitation_respond',
          params: <String, dynamic>{
            'p_invitation_id': invitationId.value,
            'p_accept': accept,
          },
        ));
  }

  Future<TeamGuestPlayerId> addGuest(TeamId teamId, String displayName) async {
    final id = await _guard(() => _client.rpc<String>(
          'team_add_guest',
          params: <String, dynamic>{
            'p_team_id': teamId.value,
            'p_display_name': displayName,
          },
        ));
    return TeamGuestPlayerId(id);
  }

  Future<void> removeMember(TeamId teamId, UserId memberUserId) {
    return _guard(() => _client.rpc<void>(
          'team_remove_member',
          params: <String, dynamic>{
            'p_team_id': teamId.value,
            'p_member_user_id': memberUserId.value,
          },
        ));
  }

  Future<void> removeGuest(TeamId teamId, TeamGuestPlayerId guestPlayerId) {
    return _guard(() => _client.rpc<void>(
          'team_remove_guest',
          params: <String, dynamic>{
            'p_team_id': teamId.value,
            'p_guest_player_id': guestPlayerId.value,
          },
        ));
  }

  Future<void> leave(TeamId teamId) {
    return _guard(() => _client.rpc<void>(
          'team_leave',
          params: <String, dynamic>{'p_team_id': teamId.value},
        ));
  }

  Future<void> dissolve(TeamId teamId) {
    return _guard(() => _client.rpc<void>(
          'team_dissolve',
          params: <String, dynamic>{'p_team_id': teamId.value},
        ));
  }

  /// Centralised error mapping: SQLSTATE `42501` becomes a permission
  /// error, token-prefixed messages map to their dedicated exception
  /// types, and the remaining tokens land in a generic
  /// [TeamOperationException] so the UI can still localize them.
  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on PostgrestException catch (e) {
      throw _mapException(e);
    }
  }

  Exception _mapException(PostgrestException e) {
    if (e.code == '42501') {
      return TeamPermissionException(e.message);
    }
    final message = e.message;
    if (message.startsWith('INVITATION_ALREADY_PENDING')) {
      return TeamInvitationDuplicateException(message);
    }
    if (message.startsWith('DISSOLVE_NEEDS_CONSENT')) {
      return TeamDissolveNeedsConsentException(message);
    }
    for (final token in const <String>[
      'TARGET_NOT_MEMBER',
      'TARGET_NOT_GUEST',
      'TEAM_DISSOLVED',
      'NOT_POOL_MEMBER',
      'NOT_AUTHENTICATED',
    ]) {
      if (message.startsWith(token)) {
        return TeamOperationException(token, message);
      }
    }
    return e;
  }
}

final teamRepositoryProvider = Provider<TeamRepository>((ref) {
  return TeamRepository(client: Supabase.instance.client);
});
