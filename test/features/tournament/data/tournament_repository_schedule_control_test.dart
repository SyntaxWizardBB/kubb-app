// ADR-0031 Phase B, Block B2c — TournamentRepository pause/resume/skip impls.
//
// Contract: each control method forwards to the matching B2s control RPC
// (migration `20261256000000`) with the tournament id under the `p_tournament_id`
// parameter named in the function signature. The four pre-B2c UnimplementedError
// stubs must be gone.

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
class _FakeFilterBuilder<T> extends Mock implements PostgrestFilterBuilder<T> {
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
  late TournamentRepository repo;

  const id = TournamentId('t-ctrl-1');

  setUp(() {
    client = _MockSupabaseClient();
    repo = TournamentRepository(
      client: client,
      realtime: FakeRealtimeChannel(),
    );
    // Every control RPC returns void; stub the typed `rpc<void>` overload.
    when(
      () => client.rpc<void>(any(), params: any(named: 'params')),
    ).thenAnswer(
      (_) => _FakeFilterBuilder<void>(Future<void>.value()),
    );
  });

  // One row per control RPC: (method under test, expected RPC name).
  final cases = <({
    String rpcName,
    Future<void> Function() invoke,
  })>[
    (rpcName: 'tournament_pause', invoke: () => repo.pauseTournament(id)),
    (rpcName: 'tournament_resume', invoke: () => repo.resumeTournament(id)),
    (
      rpcName: 'tournament_skip_forward',
      invoke: () => repo.skipScheduleForward(id),
    ),
    (
      rpcName: 'tournament_skip_back',
      invoke: () => repo.skipScheduleBackward(id),
    ),
  ];

  for (final c in cases) {
    test('${c.rpcName}: calls the RPC with p_tournament_id', () async {
      await c.invoke();

      final captured = verify(
        () => client.rpc<void>(
          c.rpcName,
          params: captureAny(named: 'params'),
        ),
      ).captured.single as Map<String, dynamic>;
      expect(captured['p_tournament_id'], id.value);
    });

    test('${c.rpcName}: no longer throws UnimplementedError', () async {
      // The invoke above resolves through the stubbed RPC; an unimplemented
      // stub would have thrown synchronously before reaching the client.
      await expectLater(c.invoke(), completes);
    });
  }
}
