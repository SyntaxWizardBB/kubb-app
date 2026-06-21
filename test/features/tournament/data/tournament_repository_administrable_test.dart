// ADR-0031 Phase B, Block B1c — TournamentRepository.listAdministrableTournaments.
//
// Contract: the repo calls the `tournament_list_administrable` RPC with the
// default `p_limit` (50, mirroring listTournaments) and decodes the returned
// rows through `tournamentAdminCardRefFromRow` into List<TournamentAdminCardRef>.
// The pre-B1c UnimplementedError stub must be gone.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

/// `PostgrestBuilder` implements `Future`, so the repo awaits the builder
/// returned by `rpc`. This fake resolves that await to a known value without
/// constructing the real builder.
class _FakeFilterBuilder<T> extends Mock
    implements PostgrestFilterBuilder<T> {
  _FakeFilterBuilder(this._future);
  final Future<T> _future;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) {
    return _future.then(onValue, onError: onError);
  }
}

void main() {
  late _MockSupabaseClient client;

  setUp(() {
    client = _MockSupabaseClient();
  });

  test(
      'listAdministrableTournaments calls tournament_list_administrable with '
      'p_limit and decodes the rows', () async {
    final rows = <dynamic>[
      <String, dynamic>{
        'tournament_id': 't-1',
        'display_name': 'Liga A',
        'format': 'swiss',
        'status': 'live',
        'current_round': 2,
        'schedule_status': 'call',
        'paused_at': null,
        'remaining_seconds': 600,
        'open_match_count': 4,
        'disputed_match_count': 1,
      },
      <String, dynamic>{
        'tournament_id': 't-2',
        'display_name': 'Liga C',
        'format': 'round_robin',
        'status': 'published',
        'current_round': null,
        'schedule_status': null,
        'paused_at': null,
        'remaining_seconds': null,
        'open_match_count': 0,
        'disputed_match_count': 0,
      },
    ];

    when(
      () => client.rpc<List<dynamic>>(
        'tournament_list_administrable',
        params: any(named: 'params'),
      ),
    ).thenAnswer(
      (_) => _FakeFilterBuilder<List<dynamic>>(Future<List<dynamic>>.value(rows)),
    );

    final repo = TournamentRepository(
      client: client,
      realtime: FakeRealtimeChannel(),
    );

    final result = await repo.listAdministrableTournaments();

    expect(result, hasLength(2));
    expect(result[0].tournamentId, const TournamentId('t-1'));
    expect(result[0].format, TournamentFormat.schoch);
    expect(result[0].scheduleStatus, RoundStatus.call);
    expect(result[0].remainingSeconds, 600);
    expect(result[1].tournamentId, const TournamentId('t-2'));
    expect(result[1].currentRound, isNull);
    expect(result[1].scheduleStatus, isNull);

    // Assert the RPC name and the p_limit param value.
    final captured = verify(
      () => client.rpc<List<dynamic>>(
        'tournament_list_administrable',
        params: captureAny(named: 'params'),
      ),
    ).captured.single as Map<String, dynamic>;
    expect(captured['p_limit'], 50);
  });

  test('listAdministrableTournaments no longer throws UnimplementedError',
      () async {
    when(
      () => client.rpc<List<dynamic>>(
        'tournament_list_administrable',
        params: any(named: 'params'),
      ),
    ).thenAnswer(
      (_) => _FakeFilterBuilder<List<dynamic>>(
        Future<List<dynamic>>.value(const <dynamic>[]),
      ),
    );

    final repo = TournamentRepository(
      client: client,
      realtime: FakeRealtimeChannel(),
    );

    final result = await repo.listAdministrableTournaments();
    expect(result, isEmpty);
  });
}
