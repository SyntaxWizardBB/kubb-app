import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/data/tournament_models.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Projects a `tournament_get` envelope into a [TournamentSummaryRef].
///
/// The envelope's inner `tournament` block is the detail header — it does
/// not carry `participant_count`. Recompute it from the sibling
/// `participants` array so the projection stays compatible with the
/// listing decoder ([tournamentSummaryRefFromRow]) without forcing the
/// RPC to expose duplicate fields.
TournamentSummaryRef _tournamentSummaryFromGetEnvelope(
  Map<String, dynamic> envelope,
) {
  final header = envelope['tournament'] as Map<String, dynamic>;
  final participants =
      envelope['participants'] as List<dynamic>? ?? const <dynamic>[];
  final creator = header['created_by'] as String?;
  return TournamentSummaryRef(
    tournamentId: TournamentId(header['tournament_id'] as String),
    displayName: header['display_name'] as String,
    format: TournamentFormatWire.fromWire(header['format'] as String),
    status: TournamentStatusWire.fromWire(header['status'] as String),
    startedAt: header['started_at'] == null
        ? null
        : DateTime.parse(header['started_at'] as String),
    completedAt: header['completed_at'] == null
        ? null
        : DateTime.parse(header['completed_at'] as String),
    participantCount: participants.length,
    createdBy: creator == null ? null : UserId(creator),
  );
}

/// Thrown when `tournament_organizer_override_pairing` rejects the call.
/// The server raises one of a fixed set of token-prefixed exceptions
/// (`MISSING_REASON:`, `MATCH_NOT_FOUND:`, `MATCH_ALREADY_STARTED:`,
/// `INVALID_PARTICIPANT:`, `PARTICIPANT_CONFLICT:`, `NOT_ORGANIZER:`);
/// callers can switch on [code] to render a localized message.
///
/// See migration `20260601000013_rpc_tournament_organizer_override_pairing`.
class OverrideKoPairingException implements Exception {
  const OverrideKoPairingException(this.code, this.message);

  /// One of: `MISSING_REASON`, `MATCH_NOT_FOUND`, `MATCH_ALREADY_STARTED`,
  /// `INVALID_PARTICIPANT`, `PARTICIPANT_CONFLICT`, `NOT_ORGANIZER`,
  /// or `UNKNOWN` when the server emitted an unmapped token.
  final String code;
  final String message;

  @override
  String toString() => 'OverrideKoPairingException($code): $message';
}

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
    return _tournamentSummaryFromGetEnvelope(response);
  }

  @override
  Future<TournamentDetail?> getTournamentDetail(TournamentId id) async {
    final response = await _client.rpc<Map<String, dynamic>?>(
      'tournament_get',
      params: <String, dynamic>{'p_tournament_id': id.value},
    );
    if (response == null) return null;
    return tournamentDetailFromRow(response);
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

  // ---- M2 KO-phase additions (T7b) ----
  //
  // Signatures mirror the upcoming [TournamentRemote] port extension
  // landing in T7a. They satisfy that interface once the abstract
  // methods appear in the port; until then they are concrete additions
  // on the implementation class. `@override` is intentionally omitted
  // here so this branch compiles cleanly against the pre-T7a port.

  /// Forwards a `(participantId -> seed)` map into the
  /// `tournament_set_seeding` RPC. Server validates that all keys are
  /// confirmed participants and that seeds are unique.
  Future<void> setSeeding({
    required TournamentId tournamentId,
    required Map<TournamentParticipantId, int> seeds,
  }) {
    return _client.rpc<void>(
      'tournament_set_seeding',
      params: <String, dynamic>{
        'p_tournament_id': tournamentId.value,
        'p_seeds': seedingMapToWire(seeds),
      },
    );
  }

  /// Calls `tournament_start_ko_phase`. Per ADR-0017 §7 the server
  /// surfaces an already-initialised bracket as `ERRCODE 40001`
  /// (`serialization_failure`); this adapter swallows that code so the
  /// caller sees an idempotent success and refreshes its state instead
  /// of showing an error toast.
  Future<void> startKoPhase(
    TournamentId tournamentId,
    KoPhaseConfig config,
  ) async {
    try {
      await _client.rpc<void>(
        'tournament_start_ko_phase',
        params: <String, dynamic>{
          'p_tournament_id': tournamentId.value,
          'p_ko_config': config.toWire(),
        },
      );
    } on PostgrestException catch (e) {
      if (e.code == '40001') {
        // Idempotent path: KO phase already initialised on the server.
        // Caller invalidates and re-fetches instead of bubbling an error.
        return;
      }
      rethrow;
    }
  }

  /// Calls `tournament_organizer_override_pairing`. Maps the
  /// token-prefixed server messages to an [OverrideKoPairingException]
  /// so the UI layer can render a localized error without parsing
  /// strings.
  Future<void> overrideKoPairing({
    required TournamentMatchId matchId,
    required TournamentParticipantId participantA,
    required TournamentParticipantId participantB,
    required String reason,
  }) async {
    try {
      await _client.rpc<void>(
        'tournament_organizer_override_pairing',
        params: <String, dynamic>{
          'p_match_id': matchId.value,
          'p_participant_a': participantA.value,
          'p_participant_b': participantB.value,
          'p_reason': reason,
        },
      );
    } on PostgrestException catch (e) {
      throw _mapOverridePairingException(e);
    }
  }

  /// Reads KO/third-place/final match rows for [tournamentId] and
  /// rebuilds the domain [Bracket] via [bracketFromMatches]. Selecting
  /// directly through the table client lets us pick up the `phase` and
  /// `bracket_position` columns added in migration 20260601000010 — the
  /// envelope returned by `tournament_list_matches` (M1) does not
  /// expose them. RLS on `tournament_matches` filters the rows down to
  /// what the caller is allowed to see.
  Future<Bracket> getBracket(TournamentId tournamentId) async {
    final rows = await _client
        .from('tournament_matches')
        .select(
          'round_number, bracket_position, phase, '
          'participant_a, participant_b, winner_participant, status',
        )
        .eq('tournament_id', tournamentId.value)
        .inFilter('phase', const <String>['ko', 'third_place', 'final'])
        .order('round_number')
        .order('bracket_position');
    final koRows = <KoMatchRow>[
      for (final row in rows.cast<Map<String, dynamic>>())
        ?koMatchRowFromRow(row),
    ];
    return bracketFromMatches(koRows);
  }

  OverrideKoPairingException _mapOverridePairingException(
    PostgrestException e,
  ) {
    const tokens = <String>{
      'MISSING_REASON',
      'MATCH_NOT_FOUND',
      'MATCH_ALREADY_STARTED',
      'INVALID_PARTICIPANT',
      'PARTICIPANT_CONFLICT',
      'NOT_ORGANIZER',
    };
    final message = e.message;
    for (final token in tokens) {
      if (message.startsWith('$token:')) {
        return OverrideKoPairingException(token, message);
      }
    }
    return OverrideKoPairingException('UNKNOWN', message);
  }

  @override
  Stream<TournamentMatchRef> watchMatch(TournamentMatchId id) {
    // Real-time delivery lands in M4; the MVP-slice polls via the
    // detail-controller. Surfacing an empty stream keeps the port
    // satisfiable without committing to a transport.
    return const Stream<TournamentMatchRef>.empty();
  }

  @override
  Future<void> setSeeding({
    required TournamentId tournamentId,
    required Map<TournamentParticipantId, int> seeds,
  }) {
    throw UnimplementedError('setSeeding — TASK-M2.2-T7b');
  }

  @override
  Future<void> startKoPhase(TournamentId tournamentId, KoPhaseConfig config) {
    throw UnimplementedError('startKoPhase — TASK-M2.2-T7b');
  }

  @override
  Future<void> overrideKoPairing({
    required TournamentMatchId matchId,
    required TournamentParticipantId participantA,
    required TournamentParticipantId participantB,
    required String reason,
  }) {
    throw UnimplementedError('overrideKoPairing — TASK-M2.2-T7b');
  }

  @override
  Future<Bracket> getBracket(TournamentId tournamentId) {
    throw UnimplementedError('getBracket — TASK-M2.2-T7b');
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
