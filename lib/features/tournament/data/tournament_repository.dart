import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/data/tournament_models.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wrapper around the tournament-* RPCs declared in the
/// `tournament_*` migrations. Implements the [TournamentRemote] port
/// from `kubb_domain`. Every call is authenticated; the
/// SECURITY DEFINER functions on the server enforce role rules.
class TournamentRepository implements TournamentRemote {
  TournamentRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  @override
  Future<List<TournamentSummaryRef>> listTournaments({
    TournamentStatus? statusFilter,
    int limit = 50,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'tournament_list_for_caller',
      params: <String, dynamic>{
        if (statusFilter != null)
          'p_status_filter': statusFilter.toWire(),
        'p_limit': limit,
      },
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(tournamentSummaryRefFromRow)
        .toList(growable: false);
  }

  @override
  Future<TournamentSummaryRef?> getTournament(TournamentId id) async {
    final response = await _client.rpc<Map<String, dynamic>?>(
      'tournament_get',
      params: <String, dynamic>{'p_tournament_id': id.value},
    );
    if (response == null) return null;
    // The RPC returns the full TournamentDetail jsonb; callers that
    // only need the summary use the header subset.
    return tournamentSummaryRefFromRow(
      response['tournament'] as Map<String, dynamic>,
    );
  }

  /// Variant of [getTournament] that decodes the full detail payload.
  Future<TournamentDetail?> getTournamentDetail(TournamentId id) async {
    final response = await _client.rpc<Map<String, dynamic>?>(
      'tournament_get',
      params: <String, dynamic>{'p_tournament_id': id.value},
    );
    if (response == null) return null;
    return TournamentDetail.fromRow(response);
  }

  @override
  Future<TournamentId> createTournament({
    required String displayName,
    required int teamSize,
    required int minParticipants,
    required int maxParticipants,
    required TournamentFormat format,
    required Map<String, Object?> matchFormatConfig,
    required List<String> tiebreakerOrder,
  }) async {
    final response = await _client.rpc<Map<String, dynamic>>(
      'tournament_create',
      params: <String, dynamic>{
        'p_display_name': displayName,
        'p_team_size': teamSize,
        'p_min_participants': minParticipants,
        'p_max_participants': maxParticipants,
        'p_format': format.toWire(),
        'p_match_format_config': matchFormatConfig,
        'p_tiebreaker_order': tiebreakerOrder,
      },
    );
    return TournamentId(response['tournament_id']! as String);
  }

  @override
  Future<void> publish(TournamentId id) =>
      _voidRpc('tournament_publish', id);

  @override
  Future<void> openRegistration(TournamentId id) =>
      _voidRpc('tournament_open_registration', id);

  @override
  Future<void> closeRegistration(TournamentId id) =>
      _voidRpc('tournament_close_registration', id);

  @override
  Future<void> startTournament(TournamentId id) =>
      _voidRpc('tournament_start', id);

  @override
  Future<void> finalizeTournament(TournamentId id) =>
      _voidRpc('tournament_finalize', id);

  @override
  Future<void> abortTournament(TournamentId id) =>
      _voidRpc('tournament_abort', id);

  @override
  Future<TournamentParticipantId> registerSingle(TournamentId id) async {
    final response = await _client.rpc<Map<String, dynamic>>(
      'tournament_register_single',
      params: <String, dynamic>{'p_tournament_id': id.value},
    );
    return TournamentParticipantId(response['participant_id']! as String);
  }

  @override
  Future<void> withdrawRegistration(TournamentParticipantId participantId) =>
      _voidParticipantRpc('tournament_withdraw', participantId);

  @override
  Future<void> confirmRegistration(TournamentParticipantId participantId) =>
      _voidParticipantRpc(
        'tournament_confirm_registration',
        participantId,
      );

  @override
  Future<void> rejectRegistration(TournamentParticipantId participantId) =>
      _voidParticipantRpc(
        'tournament_reject_registration',
        participantId,
      );

  @override
  Future<List<TournamentMatchRef>> listMatchesForTournament(
      TournamentId id) async {
    final rows = await _client.rpc<List<dynamic>>(
      'tournament_list_matches',
      params: <String, dynamic>{'p_tournament_id': id.value},
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(tournamentMatchRefFromRow)
        .toList(growable: false);
  }

  @override
  Future<TournamentMatchRef?> getMatch(TournamentMatchId id) async {
    final response = await _client.rpc<Map<String, dynamic>?>(
      'tournament_match_get',
      params: <String, dynamic>{'p_match_id': id.value},
    );
    if (response == null) return null;
    return tournamentMatchRefFromRow(response);
  }

  @override
  Future<void> proposeSetScores({
    required TournamentMatchId matchId,
    required int consensusRound,
    required List<SetScore> setScores,
  }) {
    return _client.rpc<void>(
      'tournament_propose_set_scores',
      params: <String, dynamic>{
        'p_match_id': matchId.value,
        'p_consensus_round': consensusRound,
        'p_set_scores': [
          for (var i = 0; i < setScores.length; i++)
            _setScoreToWire(i + 1, setScores[i]),
        ],
      },
    );
  }

  @override
  Future<void> organizerOverride({
    required TournamentMatchId matchId,
    required List<SetScore> finalSetScores,
    required String reason,
  }) {
    return _client.rpc<void>(
      'tournament_organizer_override',
      params: <String, dynamic>{
        'p_match_id': matchId.value,
        'p_final_set_scores': [
          for (var i = 0; i < finalSetScores.length; i++)
            _setScoreToWire(i + 1, finalSetScores[i]),
        ],
        'p_reason': reason,
      },
    );
  }

  @override
  Stream<TournamentMatchRef> watchMatch(TournamentMatchId id) {
    // Real-time delivery lands in M4; the MVP-slice polls via the
    // detail-controller. Surfacing an empty stream keeps the port
    // satisfiable without committing to a transport.
    return const Stream<TournamentMatchRef>.empty();
  }

  Future<void> _voidRpc(String fn, TournamentId id) {
    return _client.rpc<void>(
      fn,
      params: <String, dynamic>{'p_tournament_id': id.value},
    );
  }

  Future<void> _voidParticipantRpc(
    String fn,
    TournamentParticipantId participantId,
  ) {
    return _client.rpc<void>(
      fn,
      params: <String, dynamic>{'p_participant_id': participantId.value},
    );
  }

  Map<String, dynamic> _setScoreToWire(int setNumber, SetScore s) {
    return <String, dynamic>{
      'set': setNumber,
      'basekubbs_a': s.basekubbsKnockedByA,
      'basekubbs_b': s.basekubbsKnockedByB,
      'winner': s.winner == SetWinner.teamA ? 'A' : 'B',
    };
  }
}

final tournamentRemoteProvider = Provider<TournamentRemote>((ref) {
  return TournamentRepository(client: Supabase.instance.client);
});
