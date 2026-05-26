import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/team/data/team_models.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final isAuthed = ref.watch(isAuthenticatedProvider);
  if (!isAuthed) return const <PendingTeamInvitation>[];

  final client = Supabase.instance.client;
  final rows = await client
      .from('team_invitations')
      .select(
        'id, team_id, invited_by, created_at, '
        'teams!inner(id, display_name, league_membership, created_at, '
        'logo_url, country, dissolved_at)',
      )
      .eq('state', 'pending')
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
  }) async {
    await _ref
        .read(teamRepositoryProvider)
        .respondInvitation(id, accept: accept);
    _ref.invalidate(pendingInvitationsProvider);
  }
}
