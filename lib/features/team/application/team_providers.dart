import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/team/application/team_detail_provider.dart';
import 'package:kubb_app/features/team/application/team_list_provider.dart';
import 'package:kubb_app/features/team/data/team_models.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Polling sentinel for the team detail screen. A screen that
/// `ref.watch`es this keeps a Timer alive that invalidates
/// [teamDetailProvider] for that team every few seconds, so a change made
/// on another device (e.g. an invitee accepting) appears without a manual
/// refresh. Auto-disposes when the screen unmounts. Mirrors
/// `friendsPollingProvider` / `inboxPollingProvider`.
// ignore: specify_nonobvious_property_types
final teamDetailPollingProvider =
    Provider.autoDispose.family<void, TeamId>((ref, teamId) {
  final timer = Timer.periodic(
    const Duration(seconds: 4),
    (_) => ref.invalidate(teamDetailProvider(teamId)),
  );
  ref.onDispose(timer.cancel);
});

/// Polling sentinel for the "Meine Teams" list — invalidates
/// [teamListProvider] every few seconds while the list screen is mounted.
// ignore: specify_nonobvious_property_types
final teamListPollingProvider = Provider.autoDispose<void>((ref) {
  final timer = Timer.periodic(
    const Duration(seconds: 4),
    (_) => ref.invalidate(teamListProvider),
  );
  ref.onDispose(timer.cancel);
});

/// One pending team invitation joined with its team header, as needed by
/// the invitation screen. The repository's `team_invitations` rows do
/// not carry the team's display name, so we fetch both in one PostgREST
/// call via the foreign-key join syntax exposed by Supabase RLS.
class PendingTeamInvitation {
  const PendingTeamInvitation({
    required this.invitationId,
    required this.team,
    required this.invitedByUserId,
    required this.createdAt,
  });

  final TeamInvitationId invitationId;
  final TeamWire team;
  final String invitedByUserId;
  final DateTime createdAt;
}

/// Stand-in for the M3.1-T10 controller surface: lists the caller's
/// `state = 'pending'` invitations. Once T10 lands this provider becomes
/// the thin shim it always intended to be.
final pendingInvitationsProvider =
    FutureProvider<List<PendingTeamInvitation>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const <PendingTeamInvitation>[];

  final client = Supabase.instance.client;
  // Scope to invitations addressed TO the caller. The RLS read policy also
  // lets pool members (e.g. the inviter) read a team's pending invitations, so
  // without this filter an inviter would see the invites they sent and tapping
  // "accept" would fail with `caller is not the invitee`.
  final rows = await client
      .from('team_invitations')
      .select(
        'id, team_id, invited_by, created_at, '
        'teams!inner(id, display_name, league_membership, created_at, '
        'logo_url, country, dissolved_at)',
      )
      .eq('state', 'pending')
      .eq('invitee_user_id', userId)
      .order('created_at', ascending: false);

  return rows.map<PendingTeamInvitation>((row) {
    final teamRaw = row['teams'] as Map<String, dynamic>;
    final teamJson = <String, dynamic>{
      'team_id': teamRaw['id'],
      'display_name': teamRaw['display_name'],
      'league_membership': teamRaw['league_membership'],
      'created_at': teamRaw['created_at'],
      'logo_url': teamRaw['logo_url'],
      'country': teamRaw['country'],
      'dissolved_at': teamRaw['dissolved_at'],
    };
    return PendingTeamInvitation(
      invitationId: TeamInvitationId(row['id'] as String),
      team: TeamWire.fromJson(teamJson),
      invitedByUserId: row['invited_by'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }).toList(growable: false);
});

/// Whether the league transfer window (Oct–Feb) is currently open, decided by
/// the server clock — so the edit UI can enable/disable the league control
/// without trusting the device time.
final leagueWindowOpenProvider = FutureProvider<bool>((ref) async {
  return ref.read(teamRepositoryProvider).leagueWindowOpen();
});

/// Imperative action surface for the invitation screen. Routes through
/// [TeamRepository] and invalidates [pendingInvitationsProvider] so the
/// list re-renders without a manual pull-to-refresh.
final teamActionsProvider = Provider<TeamActions>(TeamActions.new);

class TeamActions {
  TeamActions(this._ref);
  final Ref _ref;

  Future<void> respondInvitation(
    TeamInvitationId id, {
    required bool accept,
    TeamId? teamId,
  }) async {
    await _ref
        .read(teamRepositoryProvider)
        .respondInvitation(id, accept: accept);
    _ref.invalidate(pendingInvitationsProvider);
    // R19-F-17: an accepted invitation grows the caller's pool roster
    // and adds the team to "Meine Teams". The list/detail caches are
    // FutureProviders driven by `team_get` / `list_my_teams` RPCs, so
    // without an explicit invalidation the user lands on a detail
    // screen that still hides them from the pool until the next cold
    // start. A decline only needs the invitation list refresh.
    if (accept) {
      _ref.invalidate(teamListProvider);
      if (teamId != null) _ref.invalidate(teamDetailProvider(teamId));
    }
  }
}
