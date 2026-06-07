import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

/// `PostgrestBuilder` implements `Future`, so `startKoPhase` awaits the
/// builder returned by `rpc`. This fake resolves that await to a value or
/// surfaces an error without constructing the real builder.
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

/// CF6 (ChangeSpec K19) — repository-level mapping of the server's
/// manual-seeding gate. The migration raises ERRCODE 22023 with a
/// `seeding_required` message prefix; [TournamentRepository.startKoPhase]
/// must surface that as a typed [SeedingRequiredException] (so the UI can
/// route to the seeding screen) while leaving the 40001 idempotency path
/// untouched.
void main() {
  late _MockSupabaseClient client;
  const tid = TournamentId('t-1');
  final config = KoPhaseConfig(
    qualifierCount: 4,
    participantCount: 4,
    seedingMode: SeedingMode.manual,
  );

  setUp(() {
    client = _MockSupabaseClient();
  });

  test('22023 + seeding_required prefix maps to SeedingRequiredException',
      () async {
    when(
      () => client.rpc<void>('tournament_start_ko_phase',
          params: any(named: 'params')),
    ).thenAnswer(
      (_) => _FakeFilterBuilder<void>(
        Future<void>.error(
          const PostgrestException(
            message: 'seeding_required: manual seeding must be set '
                'before KO start',
            code: '22023',
          ),
        ),
      ),
    );

    final repo = TournamentRepository(
      client: client,
      realtime: FakeRealtimeChannel(),
    );

    await expectLater(
      () => repo.startKoPhase(tid, config),
      throwsA(isA<SeedingRequiredException>()),
    );
  });

  test('40001 idempotency path is NOT mapped to SeedingRequiredException',
      () async {
    when(
      () => client.rpc<void>('tournament_start_ko_phase',
          params: any(named: 'params')),
    ).thenAnswer(
      (_) => _FakeFilterBuilder<void>(
        Future<void>.error(
          const PostgrestException(
            message: 'ALREADY_STARTED: ko phase already initialised',
            code: '40001',
          ),
        ),
      ),
    );

    final repo = TournamentRepository(
      client: client,
      realtime: FakeRealtimeChannel(),
    );

    // Swallowed as an idempotent success — no throw.
    await repo.startKoPhase(tid, config);
  });

  test('a plain 22023 without the seeding_required prefix is rethrown',
      () async {
    when(
      () => client.rpc<void>('tournament_start_ko_phase',
          params: any(named: 'params')),
    ).thenAnswer(
      (_) => _FakeFilterBuilder<void>(
        Future<void>.error(
          const PostgrestException(
            message: 'INVALID_KO_CONFIG: qualifier_count out of range',
            code: '22023',
          ),
        ),
      ),
    );

    final repo = TournamentRepository(
      client: client,
      realtime: FakeRealtimeChannel(),
    );

    await expectLater(
      () => repo.startKoPhase(tid, config),
      throwsA(isA<PostgrestException>()),
    );
  });
}
