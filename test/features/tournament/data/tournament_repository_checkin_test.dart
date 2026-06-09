// ADR-0031 Phase D, Block D3 — TournamentRepository check-in / undo / watch.
//
// Port contract:
//  * checkinParticipant -> RPC `tournament_checkin_participant` with the
//    participant id under `p_participant_id` (D1 migration 20261265000000).
//  * undoCheckin        -> RPC `tournament_undo_checkin` with `p_participant_id`.
//  * watchTournamentParticipants subscribes to the per-tournament
//    `tournament_participants` CDC slice (filter column `tournament_id`) and
//    projects each row through the participant CDC parser — no Timer.periodic.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

/// `PostgrestBuilder` implements `Future`, so the repo awaits the builder
/// returned by `rpc`. This fake resolves that await without constructing the
/// real builder.
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

const _pid = TournamentParticipantId('p-checkin-1');
const _tid = TournamentId('t-checkin-1');

RealtimeChange _participantInsert(Map<String, Object?> row) => RealtimeChange(
      eventType: RealtimeEventType.insert,
      table: 'tournament_participants',
      rowId: row['id']! as String,
      newRow: row,
      oldRow: const <String, Object?>{},
      receivedAt: DateTime.utc(2026, 6, 9, 8),
    );

Map<String, Object?> _participantRow({String? checkedInAt}) => <String, Object?>{
      'id': _pid.value,
      'tournament_id': _tid.value,
      'user_id': 'u-1',
      'registration_status': 'confirmed',
      'seed': null,
      'registered_at': '2026-05-24T10:00:00.000Z',
      'responded_at': null,
      'checked_in_at': checkedInAt,
    };

void main() {
  late _MockSupabaseClient client;
  late FakeRealtimeChannel channel;
  late TournamentRepository repo;

  setUp(() {
    client = _MockSupabaseClient();
    channel = FakeRealtimeChannel();
    repo = TournamentRepository(client: client, realtime: channel);
    when(
      () => client.rpc<void>(any(), params: any(named: 'params')),
    ).thenAnswer((_) => _FakeFilterBuilder<void>(Future<void>.value()));
  });

  final rpcCases = <({String rpcName, Future<void> Function() invoke})>[
    (
      rpcName: 'tournament_checkin_participant',
      invoke: () => repo.checkinParticipant(_pid),
    ),
    (rpcName: 'tournament_undo_checkin', invoke: () => repo.undoCheckin(_pid)),
  ];

  for (final c in rpcCases) {
    test('${c.rpcName}: calls the RPC with p_participant_id', () async {
      await c.invoke();
      final captured = verify(
        () => client.rpc<void>(c.rpcName, params: captureAny(named: 'params')),
      ).captured.single as Map<String, dynamic>;
      expect(captured['p_participant_id'], _pid.value);
    });
  }

  test('check-in RPC errors propagate (no client-side swallowing)', () async {
    when(
      () => client.rpc<void>(
        'tournament_checkin_participant',
        params: any(named: 'params'),
      ),
    ).thenAnswer(
      (_) => _FakeFilterBuilder<void>(
        Future<void>.error(
          const PostgrestException(message: 'forbidden', code: '42501'),
        ),
      ),
    );
    await expectLater(repo.checkinParticipant(_pid), throwsA(isA<Object>()));
  });

  test(
    'watchTournamentParticipants subscribes to the participants CDC slice',
    () async {
      final received = <TournamentParticipant>[];
      final sub = repo.watchTournamentParticipants(_tid).listen(received.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      // Emitting on the table/filterColumn-keyed channel proves the repo
      // subscribed with table:'tournament_participants', filter
      // column:'tournament_id'.
      final key = fakeRealtimeChannelKey(
        table: 'tournament_participants',
        filterColumn: 'tournament_id',
        filterValue: _tid.value,
      );
      channel.emit(
        key,
        _participantInsert(_participantRow(
          checkedInAt: '2026-06-09T08:30:00.000Z',
        )),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.participantId, _pid.value);
      expect(received.single.isCheckedIn, isTrue);
    },
  );

  test('watchTournamentParticipants drops DELETE events', () async {
    final received = <TournamentParticipant>[];
    final sub = repo.watchTournamentParticipants(_tid).listen(received.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero);

    final key = fakeRealtimeChannelKey(
      table: 'tournament_participants',
      filterColumn: 'tournament_id',
      filterValue: _tid.value,
    );
    channel.emit(
      key,
      RealtimeChange(
        eventType: RealtimeEventType.delete,
        table: 'tournament_participants',
        rowId: _pid.value,
        newRow: const <String, Object?>{},
        oldRow: _participantRow(),
        receivedAt: DateTime.utc(2026, 6, 9, 8),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
  });

  test('repository source has no new Timer.periodic for participants', () {
    final src = File(
      'lib/features/tournament/data/tournament_repository.dart',
    ).readAsStringSync();
    expect(src.contains('Timer.periodic'), isFalse);
  });
}
