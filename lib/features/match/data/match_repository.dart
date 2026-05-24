import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/match/data/match_config_draft.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Echo returned by `match_propose_result` after a participant submits
/// a round result. The status reflects whether the round (or the whole
/// match) advanced as a side-effect of this proposal.
class MatchProposeResultResponse {
  const MatchProposeResultResponse({
    required this.status,
    required this.round,
  });

  factory MatchProposeResultResponse.fromRow(Map<String, dynamic> row) {
    final roundRaw = row['round'];
    return MatchProposeResultResponse(
      status: MatchStatus.fromWire(row['status'] as String),
      round: roundRaw is int ? roundRaw : (roundRaw as num).toInt(),
    );
  }

  final MatchStatus status;
  final int round;
}

/// Wrapper around the multi-player match RPCs declared in the
/// `match_*` migrations. Every call is authenticated; the
/// SECURITY DEFINER functions on the server enforce participation /
/// ownership rules.
class MatchRepository {
  MatchRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<String> create(
    MatchConfigDraft draft, {
    required String callerUserId,
  }) async {
    final response = await _client.rpc<Map<String, dynamic>>(
      'match_create',
      params: <String, dynamic>{
        'p_format': draft.format.toWire(),
        'p_scoring': draft.scoring.toWire(),
        'p_team_a': draft.teamA
            .map((s) => s.toRpcArgs(callerUserId))
            .toList(growable: false),
        'p_team_b': draft.teamB
            .map((s) => s.toRpcArgs(callerUserId))
            .toList(growable: false),
      },
    );
    return response['match_id']! as String;
  }

  Future<List<MatchSummary>> listForCaller({
    MatchStatus? statusFilter,
  }) async {
    final params = <String, dynamic>{};
    if (statusFilter != null) {
      params['p_status'] = _statusToWire(statusFilter);
    }
    final rows = await _client.rpc<List<dynamic>>(
      'match_list_for_caller',
      params: params,
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(MatchSummary.fromRow)
        .toList(growable: false);
  }

  Future<MatchDetail?> detail(String matchId) async {
    // `match_get` returns jsonb (a single object). The RPC returns null
    // if the caller is neither participant nor invited observer; the
    // PostgREST client surfaces that as a Dart `null`.
    final response = await _client.rpc<Map<String, dynamic>?>(
      'match_get',
      params: <String, dynamic>{'p_match_id': matchId},
    );
    if (response == null) return null;
    return MatchDetail.fromRow(response);
  }

  Future<void> respondToInvite(
    String matchId, {
    required bool accept,
  }) {
    return _client.rpc<void>(
      'match_invite_response',
      params: <String, dynamic>{
        'p_match_id': matchId,
        'p_accept': accept,
      },
    );
  }

  Future<void> finishPlay(String matchId) {
    return _client.rpc<void>(
      'match_finish_play',
      params: <String, dynamic>{'p_match_id': matchId},
    );
  }

  Future<MatchProposeResultResponse> proposeResult(
    String matchId, {
    required String? winnerTeamId,
    required int scoreA,
    required int scoreB,
  }) async {
    final response = await _client.rpc<Map<String, dynamic>>(
      'match_propose_result',
      params: <String, dynamic>{
        'p_match_id': matchId,
        'p_winner_team_id': winnerTeamId,
        'p_score_a': scoreA,
        'p_score_b': scoreB,
      },
    );
    return MatchProposeResultResponse.fromRow(response);
  }

  Future<void> cancel(String matchId) {
    return _client.rpc<void>(
      'match_cancel',
      params: <String, dynamic>{'p_match_id': matchId},
    );
  }

  String _statusToWire(MatchStatus status) {
    switch (status) {
      case MatchStatus.pendingInvites:
        return 'pending_invites';
      case MatchStatus.active:
        return 'active';
      case MatchStatus.awaitingResults:
        return 'awaiting_results';
      case MatchStatus.finalized:
        return 'finalized';
      case MatchStatus.voided:
        return 'voided';
    }
  }
}

final matchRepositoryProvider = Provider<MatchRepository>((ref) {
  return MatchRepository(client: Supabase.instance.client);
});
