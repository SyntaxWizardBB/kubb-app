import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/application/outbox_flusher_provider.dart'
    show outboxFlusherProvider, scoreSubmissionOutboxDaoProvider;
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/device_id_provider.dart';
import 'package:kubb_app/core/data/realtime/supabase_realtime_channel.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/match/application/lamport_clock_provider.dart'
    show lamportClockProvider;
import 'package:kubb_app/features/tournament/data/tournament_models.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide RealtimeChannel;

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

/// Thrown when `tournament_register_team` rejects the call because no
/// roster slot references a registered user. The server raises
/// `ERRCODE 22023` with `HINT 'MIN_ONE_REGISTERED'` per FR-REG-12; this
/// exception lets the UI surface the rule-specific message without
/// parsing strings.
///
/// See migration `20260615000006_tournament_team_rpcs`.
class MinOneRegisteredException implements Exception {
  const MinOneRegisteredException(this.message);

  final String message;

  @override
  String toString() => 'MinOneRegisteredException: $message';
}

/// Thrown when a roster insert collides with the BR-5 trigger from
/// migration `20260615000005_tournament_team_roster` — a player already
/// holds an open slot for another team in the same tournament. The
/// server raises Postgres `ERRCODE 23P01` (`exclusion_violation`) with
/// `HINT 'BR_5_VIOLATION'`.
class RosterBR5Exception implements Exception {
  const RosterBR5Exception(this.message);

  final String message;

  @override
  String toString() => 'RosterBR5Exception: $message';
}

/// Thrown when `tournament_roster_replace` rejects the call because the
/// roster is locked. [cause] is `match-open` when a match the
/// participant is part of is awaiting results (OD-M3-07,
/// `HINT 'ROSTER_LOCKED_DURING_MATCH'`) and `tournament-finalized` when
/// the tournament itself is locked (FR-TEAM-15, `HINT 'ROSTER_LOCKED'`).
class RosterLockedException implements Exception {
  const RosterLockedException({required this.cause, required this.message});

  /// `match-open` or `tournament-finalized`.
  final String cause;
  final String message;

  @override
  String toString() => 'RosterLockedException($cause): $message';
}

/// Thrown when a pool-cut step cannot break a tie via the configured
/// tiebreaker chain (OD-M3-05). The server raises
/// `TIEBREAKER_NEEDS_RESOLUTION` (`ERRCODE 40001`) with a JSON detail
/// payload listing the affected participants. The organizer then orders
/// them manually via [TournamentRemote.resolveCrossPoolTie] and retries
/// the start call.
///
/// See ADR-0019 §4 and migration adding `_tournament_compute_pool_cut`.
class TieResolutionRequiredException implements Exception {
  const TieResolutionRequiredException({
    required this.conflictingParticipants,
    required this.message,
  });

  /// Participants the server could not order. Wire payload uses
  /// `tied_participants` (ADR-0019) or `conflicting_participants`
  /// (tasks.md T5); the adapter accepts both keys.
  final List<TournamentParticipantId> conflictingParticipants;
  final String message;

  @override
  String toString() =>
      'TieResolutionRequiredException(${conflictingParticipants.length}): '
      '$message';
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
  TournamentRepository({
    required SupabaseClient client,
    RealtimeChannel? realtime,
    Ref? ref,
  })  : _client = client,
        _realtime = realtime ?? SupabaseRealtimeChannel(client),
        _ref = ref;

  final SupabaseClient _client;

  /// Realtime adapter used by the `watch*` streams. Defaulted to a
  /// `SupabaseRealtimeChannel` over [_client] so existing callers that
  /// build the repository without the M4 wiring keep working; the
  /// provider will inject the shared instance once T8 lands.
  final RealtimeChannel _realtime;

  /// Riverpod ref injected by [tournamentRemoteProvider]. Used by
  /// [proposeSetScores] (TASK-M4.3-T10) to look up the outbox DAO, the
  /// per-match Lamport clock, the device id, and the outbox flusher
  /// without static singletons. Nullable so direct constructor use in
  /// older tests keeps compiling — when absent the score-submission
  /// path falls back to the legacy direct RPC call.
  final Ref? _ref;

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
  Future<List<MyTournamentRegistration>> listMyRegistrations() async {
    final rows = await _client.rpc<List<dynamic>>(
      'tournament_list_my_registrations',
      params: const <String, dynamic>{'p_limit': 50},
    );
    return rows.cast<Map<String, dynamic>>().map((row) {
      return MyTournamentRegistration(
        tournament: tournamentSummaryRefFromRow(row),
        participantId:
            TournamentParticipantId(row['participant_id']! as String),
        status: _registrationStatusFromWire(
          row['registration_status']! as String,
        ),
      );
    }).toList(growable: false);
  }

  /// Maps the raw `tournament_participants.registration_status` wire value
  /// onto the domain enum. Delegates to [TournamentParticipantStatusWire.
  /// fromWire] so this layer and the detail-payload parser share ONE
  /// mapping — they drifted apart once and a `confirmed` row then crashed
  /// only the path that hadn't been updated.
  TournamentParticipantStatus _registrationStatusFromWire(String raw) =>
      TournamentParticipantStatusWire.fromWire(raw);

  @override
  Future<TournamentId> createTournament({
    required String displayName,
    required int teamSize,
    required int minParticipants,
    required int maxParticipants,
    required TournamentFormat format,
    required Map<String, Object?> matchFormatConfig,
    required List<String> tiebreakerOrder,
    Map<String, Object?> setup = const <String, Object?>{},
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
        'p_setup': setup,
      },
    );
    return TournamentId(response['tournament_id']! as String);
  }

  @override
  Future<void> updateTournament({
    required TournamentId id,
    required String displayName,
    required int teamSize,
    required int minParticipants,
    required int maxParticipants,
    required TournamentFormat format,
    required Map<String, Object?> matchFormatConfig,
    required List<String> tiebreakerOrder,
    Map<String, Object?> setup = const <String, Object?>{},
  }) async {
    await _client.rpc<Map<String, dynamic>>(
      'tournament_update',
      params: <String, dynamic>{
        'p_tournament_id': id.value,
        'p_display_name': displayName,
        'p_team_size': teamSize,
        'p_min_participants': minParticipants,
        'p_max_participants': maxParticipants,
        'p_format': format.toWire(),
        'p_match_format_config': matchFormatConfig,
        'p_tiebreaker_order': tiebreakerOrder,
        'p_setup': setup,
      },
    );
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

  /// TASK-M4.3-T10: route every score submission through the
  /// `ScoreSubmissionOutbox` so submissions survive offline periods and
  /// app crashes. One outbox row per set is enqueued with a freshly
  /// ticked Lamport counter; immediately after the inserts we kick off
  /// `OutboxFlusher.flushPending` fire-and-forget so an online submit
  /// reaches the RPC within the same frame. The legacy direct
  /// `tournament_propose_set_scores` RPC path is intentionally removed.
  ///
  /// Falls back to the direct RPC call only when [_ref] is null — i.e.
  /// the repository was built outside of Riverpod (e.g. legacy ad-hoc
  /// constructions). Production wiring always supplies a [Ref] via
  /// [tournamentRemoteProvider].
  @override
  Future<void> proposeSetScores({
    required TournamentMatchId matchId,
    required int consensusRound,
    required List<SetScore> setScores,
  }) async {
    final ref = _ref;
    if (ref == null) {
      // No Riverpod context — keep the legacy path so direct
      // instantiations (older tests) keep working until they migrate.
      await _client.rpc<void>(
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
      return;
    }

    final submitterUserId = ref.read(currentUserIdProvider);
    if (submitterUserId == null) {
      throw StateError(
        'proposeSetScores called without an authenticated user — '
        'TASK-M4.3-T10 requires a known submitter for the outbox row.',
      );
    }
    final deviceId = await ref.read(deviceIdProvider.future);
    final clock = await ref.read(
      lamportClockProvider(MatchId(matchId.value)).future,
    );
    final dao = ref.read(scoreSubmissionOutboxDaoProvider);
    final queuedAt = DateTime.now();
    for (var i = 0; i < setScores.length; i++) {
      final setIndex = i + 1;
      final score = setScores[i];
      final tick = clock.tick();
      await dao.insert(
        ScoreSubmissionOutboxCompanion.insert(
          matchId: matchId.value,
          consensusRound: consensusRound,
          setIndex: setIndex,
          submitterUserId: submitterUserId,
          lamportCounter: tick.counter,
          lamportDeviceId: deviceId,
          scoreJson: jsonEncode(_setScoreToWire(setIndex, score)),
          queuedAt: queuedAt,
          acknowledgedAt: const Value<DateTime?>(null),
        ),
      );
    }
    // Fire-and-forget: a synchronous failure inside `flushPending`
    // (network down, etc.) must not abort the submit path — the
    // submission is durably enqueued and the flusher's connectivity
    // listener will retry. We don't await to keep the UI responsive
    // when offline.
    unawaited(ref.read(outboxFlusherProvider).flushPending());
  }

  @override
  Future<TournamentMatchRef> proposeSetScoreWithLamport({
    required TournamentMatchId matchId,
    required int consensusRound,
    required int setIndex,
    required TournamentParticipantId submitter,
    required SetScore score,
    required int lamportCounter,
    required String deviceId,
  }) async {
    try {
      final row = await _client.rpc<Map<String, dynamic>>(
        'tournament_propose_set_score',
        params: <String, dynamic>{
          'p_match_id': matchId.value,
          'p_consensus_round': consensusRound,
          'p_set_index': setIndex,
          'p_score': _setScoreToWire(setIndex, score),
          'p_lamport_counter': lamportCounter,
          'p_device_id': deviceId,
        },
      );
      return tournamentMatchRefFromRow(row);
    } on PostgrestException catch (e) {
      final token = _scoreConflictTokenFromException(e);
      if (token != null) {
        throw TournamentScoreConflictException(token);
      }
      rethrow;
    }
  }

  /// Extracts the score-conflict token (e.g. `STALE_CONSENSUS_ROUND`)
  /// from a PostgREST error. The server raises the conflict via
  /// `RAISE EXCEPTION USING HINT = '<TOKEN>'` per
  /// `20260701000001_score_rpc_idempotency.sql`; PostgREST surfaces the
  /// HINT on [PostgrestException.hint]. Returns `null` when the
  /// exception does not look like a score conflict so the caller can
  /// rethrow unchanged.
  String? _scoreConflictTokenFromException(PostgrestException e) {
    const knownTokens = <String>{'STALE_CONSENSUS_ROUND'};
    final hint = e.hint;
    if (hint != null && knownTokens.contains(hint)) return hint;
    return null;
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

  /// W3-T1: forwards the no-show forfeit declaration to the
  /// `tournament_match_forfeit` RPC. The server validates the absent
  /// side, the reason length (>= 10) and the tournament status; the
  /// score is derived from `tournaments.forfeit_points`.
  @override
  Future<void> declareForfeit({
    required TournamentMatchId matchId,
    required ForfeitAbsentSide absentSide,
    required String reason,
  }) {
    return _client.rpc<void>(
      'tournament_match_forfeit',
      params: <String, dynamic>{
        'p_match_id': matchId.value,
        'p_absent_side': absentSide.toWire(),
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
  @override
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
  @override
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
      final tieEx = _tieResolutionFromException(e);
      if (tieEx != null) throw tieEx;
      if (e.code == '40001') {
        // Idempotent path: KO phase already initialised on the server.
        // Caller invalidates and re-fetches instead of bubbling an error.
        return;
      }
      rethrow;
    }
  }

  /// P6 "TournierStart" auto-seeding. Calls `tournament_autoseed_from_elo`,
  /// which persists the ELO-derived order into `tournament_seeding_overrides`
  /// (the same store [setSeeding] writes and the KO generator reads), then
  /// reads that store back so the caller renders the authoritative
  /// server-side order rather than a local prediction. Returned best-first
  /// (seed 1 .. N).
  @override
  Future<List<TournamentParticipantId>> autoseedFromElo(
    TournamentId tournamentId,
  ) async {
    await _client.rpc<void>(
      'tournament_autoseed_from_elo',
      params: <String, dynamic>{
        'p_tournament_id': tournamentId.value,
      },
    );
    final rows = await _client
        .from('tournament_seeding_overrides')
        .select('participant_id, seed_override')
        .eq('tournament_id', tournamentId.value)
        .order('seed_override');
    return <TournamentParticipantId>[
      for (final row in rows.cast<Map<String, dynamic>>())
        TournamentParticipantId(row['participant_id'] as String),
    ];
  }

  /// Calls `tournament_organizer_override_pairing`. Maps the
  /// token-prefixed server messages to an [OverrideKoPairingException]
  /// so the UI layer can render a localized error without parsing
  /// strings.
  @override
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
  @override
  Future<Bracket> getBracket(TournamentId tournamentId) async {
    final rows = await _client
        .from('tournament_matches')
        .select(
          'round_number, bracket_position, phase, '
          'participant_a, participant_b, winner_participant, status',
        )
        .eq('tournament_id', tournamentId.value)
        .inFilter('phase', const <String>[
          'ko',
          'third_place',
          'final',
          'wb',
          'lb',
          'grand_final',
          'grand_final_reset',
        ])
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
  Stream<TournamentMatchRef> watchMatch(TournamentMatchId id) async* {
    // Per OD-M4-01 / port doc-block: subscribe to the per-tournament
    // channel and filter client-side on [id]. We need the tournament id
    // to address the channel, so look it up once via the existing read
    // path. Returning an empty stream when the match is gone matches
    // the M1 placeholder contract callers may still rely on.
    final ref = await getMatch(id);
    if (ref == null) return;
    yield* watchTournamentMatches(ref.tournamentId)
        .where((r) => r.matchId == id);
  }

  @override
  Stream<TournamentMatchRef> watchTournamentMatches(TournamentId tournamentId) {
    return _realtime
        .subscribe(
          table: 'tournament_matches',
          filterColumn: 'tournament_id',
          filterValue: tournamentId.value,
        )
        .where((c) => c.eventType != RealtimeEventType.delete)
        .map((c) => tournamentMatchRefFromCdcRow(c.newRow));
  }

  @override
  Stream<BracketAdvanceEvent> watchBracketAdvances(TournamentId tournamentId) {
    // KO-advance signal: a row in [tournamentId] flips to `finalized`
    // (or `overridden`) and carries a winner. The trigger that copies
    // the winner into the parent slot fires server-side; the next
    // `update` on that parent row is what the dashboard needs to redraw.
    // Mapping the just-finalised row gives the UI both the source match
    // id and the (round, match-number) of the slot that just filled —
    // enough to invalidate the bracket view without a re-fetch.
    return _realtime
        .subscribe(
          table: 'tournament_matches',
          filterColumn: 'tournament_id',
          filterValue: tournamentId.value,
        )
        .where(_isBracketAdvanceChange)
        .map(_bracketAdvanceFromChange);
  }

  bool _isBracketAdvanceChange(RealtimeChange change) {
    if (change.eventType == RealtimeEventType.delete) return false;
    final status = change.newRow['status'];
    if (status != 'finalized' && status != 'overridden') return false;
    if (change.newRow['winner_participant'] == null) return false;
    // For updates, fire only on the transition into a terminal state —
    // re-emits of an already-finalised row would spam the dashboard.
    if (change.eventType == RealtimeEventType.update) {
      final prev = change.oldRow['status'];
      if (prev == 'finalized' || prev == 'overridden') return false;
    }
    return true;
  }

  BracketAdvanceEvent _bracketAdvanceFromChange(RealtimeChange change) {
    final row = change.newRow;
    final round = _asInt(row['round_number']);
    final matchNumber = _asInt(row['match_number_in_round']);
    return BracketAdvanceEvent(
      tournamentId: TournamentId(row['tournament_id']! as String),
      advancedMatchId: TournamentMatchId(row['id']! as String),
      // Parent slot the winner advances into: (round+1, ceil(n/2)).
      // For the final round there is no parent — the consumer treats
      // (round, matchNumber) as the addressed slot in that case.
      targetRound: round + 1,
      targetMatchNumber: (matchNumber + 1) ~/ 2,
      winnerParticipant:
          TournamentParticipantId(row['winner_participant']! as String),
      at: change.receivedAt,
    );
  }

  @override
  Future<TournamentParticipantId> registerTeam({
    required TournamentId tournamentId,
    required TeamId teamId,
    required List<RosterSlotInput> roster,
  }) async {
    try {
      final response = await _client.rpc<Map<String, dynamic>>(
        'tournament_register_team',
        params: <String, dynamic>{
          'p_tournament_id': tournamentId.value,
          'p_team_id': teamId.value,
          'p_roster_json': [
            for (final slot in roster) _rosterSlotInputToWire(slot),
          ],
        },
      );
      return TournamentParticipantId(response['participant_id']! as String);
    } on PostgrestException catch (e) {
      throw _mapRosterException(e);
    }
  }

  @override
  Future<void> replaceRosterSlot({
    required TournamentParticipantId participantId,
    required int slotIndex,
    required RosterSlotInput newOccupant,
    String? reason,
  }) async {
    try {
      await _client.rpc<void>(
        'tournament_roster_replace',
        params: <String, dynamic>{
          'p_participant_id': participantId.value,
          'p_slot_index': slotIndex,
          'p_new_member_user_id': newOccupant.memberUserId?.value,
          'p_new_guest_player_id': newOccupant.guestPlayerId?.value,
          'p_reason': reason,
        },
      );
    } on PostgrestException catch (e) {
      throw _mapRosterException(e);
    }
  }

  @override
  Future<List<RosterSlot>> getRoster(
    TournamentParticipantId participantId,
  ) async {
    // Port carries only the participant id; `tournament_roster_list`
    // needs both — fetch the tournament id from the participant row via
    // RLS-filtered select. Closed history rows (`replaced_at IS NOT
    // NULL`) are dropped client-side per the port contract.
    final row = await _client
        .from('tournament_participants')
        .select('tournament_id')
        .eq('id', participantId.value)
        .maybeSingle();
    if (row == null) return const <RosterSlot>[];
    final response = await _client.rpc<Map<String, dynamic>?>(
      'tournament_roster_list',
      params: <String, dynamic>{
        'p_tournament_id': row['tournament_id'] as String,
        'p_participant_id': participantId.value,
      },
    );
    if (response == null) return const <RosterSlot>[];
    final slots = (response['slots'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    return [
      for (final slot in slots)
        if (slot['replaced_at'] == null)
          RosterSlot.fromJson(<String, dynamic>{
            ...slot,
            'id': slot['slot_id'],
          }),
    ];
  }

  // ---- M3.3 pool-phase additions (T8) ----

  /// Calls `tournament_start_pool_phase`. Per ADR-0019 §5 the server
  /// surfaces an already-initialised phase as `ERRCODE 40001`; that
  /// path is swallowed for idempotency (mirroring `startKoPhase`). The
  /// same code is also used for `TIEBREAKER_NEEDS_RESOLUTION` — we
  /// disambiguate by message before deciding.
  @override
  Future<void> startPoolPhase(
    TournamentId tournamentId,
    PoolPhaseConfig config,
  ) async {
    try {
      await _client.rpc<void>(
        'tournament_start_pool_phase',
        params: <String, dynamic>{
          'p_tournament_id': tournamentId.value,
          'p_pool_config': config.toWire(),
        },
      );
    } on PostgrestException catch (e) {
      final tieEx = _tieResolutionFromException(e);
      if (tieEx != null) throw tieEx;
      if (e.code == '40001') {
        return; // idempotent — phase already initialised
      }
      rethrow;
    }
  }

  /// Reads `tournament_pool_standings(p_tournament_id)`. The RPC returns
  /// a `groups: [{group_label, stats: [...]}]` envelope; decoding leans
  /// on the in-package [PoolGroupStandings] value object.
  @override
  Future<List<PoolGroupStandings>> getPoolStandings(TournamentId id) async {
    final response = await _client.rpc<Map<String, dynamic>?>(
      'tournament_pool_standings',
      params: <String, dynamic>{'p_tournament_id': id.value},
    );
    if (response == null) return const <PoolGroupStandings>[];
    final groups =
        (response['groups'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>();
    return [
      for (final g in groups)
        PoolGroupStandings(
          g['group_label'] as String,
          (g['stats'] as List<dynamic>? ?? const <dynamic>[])
              .cast<Map<String, dynamic>>()
              .map(_participantStatsFromRow)
              .toList(growable: false),
        ),
    ];
  }

  /// Calls `tournament_resolve_cross_pool_tie`. The server writes the
  /// supplied order into `tournament_seeding_overrides`; the caller is
  /// expected to retry [startKoPhase] afterwards.
  @override
  Future<void> resolveCrossPoolTie(
    TournamentId tournamentId,
    List<TournamentParticipantId> orderedParticipants,
  ) {
    return _client.rpc<void>(
      'tournament_resolve_cross_pool_tie',
      params: <String, dynamic>{
        'p_tournament_id': tournamentId.value,
        'p_ordered_participant_ids': [
          for (final p in orderedParticipants) p.value,
        ],
      },
    );
  }

  // ---- P6 D2b shoot-out tiebreak (client/UI) ----

  /// Reads the open shoot-out tie groups of [tournamentId] directly from the
  /// RLS-gated `tournament_shootouts` table — D2a exposes no list-pending
  /// RPC, and RLS already scopes the rows to the organizer + registered
  /// participants. Only `pending`/`reported` rows are returned; `resolved`
  /// groups are filtered out client-side so they stop showing as open.
  ///
  /// Display names for the tied participants are resolved from the same
  /// `tournament_get` detail payload the rest of the UI uses (its
  /// `participants[]` block carries the server-projected
  /// `COALESCE(nickname, team name)` display name), avoiding a bespoke join.
  @override
  Future<List<PendingShootout>> listPendingShootouts(
    TournamentId tournamentId,
  ) async {
    final rows = await _client
        .from('tournament_shootouts')
        .select(
          'id, tournament_id, start_rank, tied_participant_ids, '
          'ordered_winners, status',
        )
        .eq('tournament_id', tournamentId.value)
        // Pending = status in ('pending','reported'); resolved groups are not
        // open anymore and must not be surfaced.
        .inFilter('status', const <String>['pending', 'reported'])
        .order('start_rank');
    final shootoutRows = rows.cast<Map<String, dynamic>>();
    if (shootoutRows.isEmpty) return const <PendingShootout>[];

    // One detail fetch resolves every participant display name.
    final detail = await getTournamentDetail(tournamentId);
    final names = <String, String?>{
      for (final p in detail?.participants ?? const <TournamentParticipant>[])
        p.participantId: p.displayName,
    };

    return [
      for (final row in shootoutRows)
        PendingShootout(
          shootoutId: row['id'] as String,
          tournamentId: TournamentId(row['tournament_id'] as String),
          startRank: _asInt(row['start_rank']),
          tiedParticipants: [
            for (final id in (row['tied_participant_ids'] as List<dynamic>? ??
                const <dynamic>[]))
              ShootoutParticipantRef(
                participantId: TournamentParticipantId(id as String),
                displayName: names[id],
              ),
          ],
          orderedWinners: [
            for (final id in (row['ordered_winners'] as List<dynamic>? ??
                const <dynamic>[]))
              TournamentParticipantId(id as String),
          ],
          status: ShootoutStatus.fromWire(row['status'] as String),
        ),
    ];
  }

  /// Reports the shoot-out winner ordering via the D2a RPC
  /// `tournament_report_shootout_winners(p_shootout_id, p_ordered_winners)`.
  @override
  Future<void> reportShootoutWinners({
    required String shootoutId,
    required List<TournamentParticipantId> orderedWinners,
  }) {
    return _client.rpc<Map<String, dynamic>>(
      'tournament_report_shootout_winners',
      params: <String, dynamic>{
        'p_shootout_id': shootoutId,
        'p_ordered_winners': [for (final p in orderedWinners) p.value],
      },
    );
  }

  /// Confirms a reported shoot-out ordering via the D2a RPC
  /// `tournament_confirm_shootout(p_shootout_id, p_ordered_winners)`. The
  /// server requires the confirmation to match the reported ordering exactly.
  @override
  Future<void> confirmShootout({
    required String shootoutId,
    required List<TournamentParticipantId> orderedWinners,
  }) {
    return _client.rpc<Map<String, dynamic>>(
      'tournament_confirm_shootout',
      params: <String, dynamic>{
        'p_shootout_id': shootoutId,
        'p_ordered_winners': [for (final p in orderedWinners) p.value],
      },
    );
  }

  ParticipantStats _participantStatsFromRow(Map<String, dynamic> row) {
    return ParticipantStats(
      participantId: row['participant_id'] as String,
      totalPoints: _asInt(row['total_points']),
      wins: _asInt(row['wins']),
      kubbsScored: _asInt(row['kubbs_scored']),
      kubbsConceded: _asInt(row['kubbs_conceded']),
      opponentIds:
          (row['opponent_ids'] as List<dynamic>? ?? const <dynamic>[])
              .cast<String>(),
      opponentTotalPointsLookup: ((row['opponent_total_points_lookup']
                  as Map<String, dynamic>?) ??
              const <String, dynamic>{})
          .map((k, v) => MapEntry(k, _asInt(v))),
      headToHeadLookup: ((row['head_to_head_lookup']
                  as Map<String, dynamic>?) ??
              const <String, dynamic>{})
          .map((k, v) => MapEntry(k, _asInt(v))),
    );
  }

  /// Matches a `TIEBREAKER_NEEDS_RESOLUTION` server raise (ADR-0019 §4):
  /// `ERRCODE 40001` + message prefix + JSON DETAIL listing the tied
  /// participants under `tied_participants` (ADR) or
  /// `conflicting_participants` (tasks.md T5). Returns `null` when [e]
  /// is some other `40001` (e.g. already-started idempotency).
  TieResolutionRequiredException? _tieResolutionFromException(
    PostgrestException e,
  ) {
    if (e.code != '40001') return null;
    if (!e.message.contains('TIEBREAKER_NEEDS_RESOLUTION')) return null;
    final detail = e.details;
    final raw = detail is String ? detail : null;
    final ids = <TournamentParticipantId>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final list = (decoded['tied_participants'] ??
              decoded['conflicting_participants']) as List<dynamic>?;
          if (list != null) {
            ids.addAll(list.cast<String>().map(TournamentParticipantId.new));
          }
        }
      } on FormatException {
        // Server didn't ship a JSON detail — leave ids empty so the
        // dialog can fall back to "manual reorder all qualifiers".
      }
    }
    return TieResolutionRequiredException(
      conflictingParticipants: List<TournamentParticipantId>.unmodifiable(ids),
      message: e.message,
    );
  }

  int _asInt(Object? r) {
    if (r is int) return r;
    if (r is num) return r.toInt();
    throw ArgumentError.value(r, 'r', 'expected num');
  }

  Map<String, dynamic> _rosterSlotInputToWire(RosterSlotInput slot) {
    return <String, dynamic>{
      'slot_index': slot.slotIndex,
      if (slot.memberUserId != null)
        'member_user_id': slot.memberUserId!.value,
      if (slot.guestPlayerId != null)
        'guest_player_id': slot.guestPlayerId!.value,
    };
  }

  Exception _mapRosterException(PostgrestException e) {
    // Server-side errors from the roster RPCs use Postgres `HINT` to
    // disambiguate (see migration 20260615000006). BR-5 is special:
    // it surfaces as `ERRCODE 23P01` from the trigger.
    if (e.code == '23P01') {
      return RosterBR5Exception(e.message);
    }
    switch (e.hint) {
      case 'MIN_ONE_REGISTERED':
        return MinOneRegisteredException(e.message);
      case 'ROSTER_LOCKED_DURING_MATCH':
        return RosterLockedException(
          cause: 'match-open',
          message: e.message,
        );
      case 'ROSTER_LOCKED':
        return RosterLockedException(
          cause: 'tournament-finalized',
          message: e.message,
        );
      default:
        return e;
    }
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
      // Sprint A W3-T2 / R11-F-01: wire the per-set king-outcome alongside
      // the legacy fields. Server migration 20260601000002 adds the
      // matching column; older servers ignore the unknown key. The
      // `king_hit_by` projection from W2 stays for backward compat with
      // RPC overloads that have not yet picked up the new token.
      'king_outcome': switch (s.kingOutcome) {
        KingHitBy() => 'hit_by',
        KingMissed() => 'missed',
        KingTimedOut() => 'timed_out',
      },
      if (s.kingOutcome case KingHitBy(:final participantId))
        'king_hit_by': participantId.value,
    };
  }
}

final tournamentRemoteProvider = Provider<TournamentRemote>((ref) {
  // Realtime adapter is composed inline: M4.1-T8 will replace this with
  // a dedicated `realtimeChannelProvider` so the same instance is
  // shared across repositories and survives re-reads.
  final client = Supabase.instance.client;
  return TournamentRepository(
    client: client,
    realtime: SupabaseRealtimeChannel(client),
    ref: ref,
  );
});
