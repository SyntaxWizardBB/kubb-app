import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
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
  TeamRepository({
    required SupabaseClient client,
    Future<WireSessionOutcome> Function()? reSignWireSession,
  })  : _client = client,
        _reSignWireSession = reSignWireSession;

  final SupabaseClient _client;

  /// Re-mints the keypair/OAuth wire session on demand. Injected from
  /// the provider so [_guard] can self-heal an expired access token
  /// (PGRST303) by re-signing once and retrying the RPC. Null in the
  /// rare construction paths that have no auth context (defensive: the
  /// guard then simply rethrows the mapped exception).
  final Future<WireSessionOutcome> Function()? _reSignWireSession;

  Future<TeamId?> createTeam({
    required String displayName,
    required LeagueMembership leagueMembership,
    String? logoUrl,
    String? country,
  }) async {
    // Type the RPC as nullable: a server crash mid-transaction (or a future
    // RPC change that stops RETURNING the id) deserialises to null. We surface
    // that as a null TeamId instead of `TeamId(null)`, so the controller's
    // null-return path produces a clean failure rather than a runtime crash.
    final id = await _guard(() => _client.rpc<String?>(
          'team_create',
          params: <String, dynamic>{
            'p_display_name': displayName,
            'p_league_membership': leagueMembership.wire,
            'p_logo_url': logoUrl,
            'p_country': country,
          },
        ));
    return id == null ? null : TeamId(id);
  }

  /// Renames the team / sets its country. Admin-only.
  Future<void> updateTeam(
    TeamId teamId, {
    required String displayName,
    String? country,
  }) {
    return _guard(() => _client.rpc<void>(
          'team_update',
          params: <String, dynamic>{
            'p_team_id': teamId.value,
            'p_display_name': displayName,
            'p_country': country,
          },
        ));
  }

  /// Changes the team's league. Admin-only and only inside the Oct–Feb window
  /// (server-checked); raises `LEAGUE_LOCKED` otherwise.
  Future<void> setLeague(TeamId teamId, LeagueMembership league) {
    return _guard(() => _client.rpc<void>(
          'team_set_league',
          params: <String, dynamic>{
            'p_team_id': teamId.value,
            'p_league': league.wire,
          },
        ));
  }

  /// Whether the league transfer window is open right now (server clock).
  Future<bool> leagueWindowOpen() {
    return _guard(() => _client.rpc<bool>('team_league_window_open'));
  }

  Future<List<TeamWire>> listMyTeams() async {
    final rows = await _guard(() => _client.rpc<List<dynamic>>(
          'team_list_for_caller',
        ));
    return rows.cast<Map<String, dynamic>>().map((row) {
      // `team_list_for_caller` returns raw `teams` rows keyed by `id`, but
      // the wire model expects `team_id` (@JsonKey). Without this remap the
      // required `id` field resolves to null and the whole "Meine Teams"
      // list fails to parse — which looked like "created teams never show up".
      final json = Map<String, dynamic>.of(row)
        ..putIfAbsent('team_id', () => row['id']);
      return TeamWire.fromJson(json);
    }).toList(growable: false);
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

  /// Invites a player by their unique nickname (case-insensitive). The server
  /// resolves the name to a user id and applies the same guards as [invite].
  /// Raises [TeamOperationException] with code `USER_NOT_FOUND` when no player
  /// carries that name.
  Future<TeamInvitationId> inviteByNickname(
    TeamId teamId,
    String nickname,
  ) async {
    final id = await _guard(() => _client.rpc<String>(
          'team_invite_by_nickname',
          params: <String, dynamic>{
            'p_team_id': teamId.value,
            'p_nickname': nickname,
          },
        ));
    return TeamInvitationId(id);
  }

  /// Adds a DB-resolved player directly to the pool as a guest-role member
  /// (no invitation). Admin-only. Raises `ALREADY_MEMBER` if the target is
  /// already in the active pool.
  Future<void> addGuestMember(TeamId teamId, UserId memberUserId) {
    return _guard(() => _client.rpc<void>(
          'team_add_guest_member',
          params: <String, dynamic>{
            'p_team_id': teamId.value,
            'p_member_user_id': memberUserId.value,
          },
        ));
  }

  /// Sets a pool member's role (`'admin'` or `'guest'`). Admin-only; the
  /// server refuses to demote the last admin (`LAST_ADMIN`).
  Future<void> setMemberRole(TeamId teamId, UserId memberUserId, String role) {
    return _guard(() => _client.rpc<void>(
          'team_set_member_role',
          params: <String, dynamic>{
            'p_team_id': teamId.value,
            'p_member_user_id': memberUserId.value,
            'p_role': role,
          },
        ));
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
      // The Phase-1 keypair JWT has a fixed lifetime and no refresh
      // token (ADR-0010). Once it expires PostgREST rejects the call
      // with PGRST303 ("JWT expired"). Re-sign the wire session once
      // and retry so a just-expired token self-heals instead of
      // surfacing as a raw error on the Teams screen.
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

  /// True when PostgREST rejected the call because the bearer JWT has
  /// expired. Supabase tags these with code `PGRST303`; we also match
  /// the message defensively in case the code is absent on some
  /// transports.
  static bool _isExpiredJwt(PostgrestException e) {
    return e.code == 'PGRST303' || e.message.contains('JWT expired');
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
      'USER_NOT_FOUND',
      'LAST_ADMIN',
      'INVALID_ROLE',
      'ALREADY_MEMBER',
      'LEAGUE_LOCKED',
      'INVALID_LEAGUE',
      'INVALID_NAME',
      'INVALID_COUNTRY',
    ]) {
      if (message.startsWith(token)) {
        return TeamOperationException(token, message);
      }
    }
    return e;
  }
}

final teamRepositoryProvider = Provider<TeamRepository>((ref) {
  return TeamRepository(
    client: Supabase.instance.client,
    // Self-healing for expired Phase-1 keypair JWTs: on PGRST303 the
    // guard re-runs the keypair wire re-sign (or OAuth refresh) and
    // retries the RPC once. Reuses the bootstrap-time mechanism rather
    // than inventing a parallel refresh path.
    reSignWireSession: () => ensureWireSession(ref, force: true),
  );
});
