// ADR-0031 Block A3c — tournamentRoundScheduleProvider /
// tournamentRoundScheduleRealtimeProvider wiring.
//
// Drives a tournament_round_schedule CDC row through a FakeTournamentRemote
// (subscribing via a shared FakeRealtimeChannel) and asserts:
//  * the realtime provider relays the parsed TournamentRoundScheduleRef,
//  * the read provider folds the latest row per (round, stageNode),
//  * no Timer.periodic poll exists in the provider source (ADR-0029).
//
// Explicit status/round arguments below spell out each emitted event for
// readability even when they match a builder default — intentional.
// ignore_for_file: avoid_redundant_argument_values

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

const _tid = TournamentId('t-sched');

Map<String, Object?> _scheduleRow({
  String? stageNodeId,
  int roundNumber = 1,
  String status = 'running',
}) =>
    <String, Object?>{
      'tournament_id': _tid.value,
      'stage_node_id': stageNodeId,
      'round_number': roundNumber,
      'phase': 'group',
      'status': status,
      'published_at': '2026-06-01T12:00:00.000Z',
      'starts_at': '2026-06-01T12:05:00.000Z',
      'ends_at': '2026-06-01T12:35:00.000Z',
      'break_seconds': 300,
      'match_seconds': 1800,
      'tiebreak_after_seconds': null,
      'paused_at': null,
      'paused_accum_seconds': 0,
    };

RealtimeChange _insert(Map<String, Object?> row) => RealtimeChange(
      eventType: RealtimeEventType.insert,
      table: 'tournament_round_schedule',
      rowId: '${row['round_number']}',
      newRow: row,
      oldRow: const <String, Object?>{},
      receivedAt: DateTime.utc(2026, 6, 1, 12),
    );

void main() {
  late FakeRealtimeChannel channel;
  late FakeTournamentRemote remote;

  setUp(() {
    channel = FakeRealtimeChannel();
    remote = FakeTournamentRemote(initialUser: const UserId('u'),
        realtime: channel);
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [tournamentRemoteProvider.overrideWithValue(remote)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('realtime provider relays a parsed schedule ref', () async {
    final c = container();
    final received = <TournamentRoundScheduleRef>[];
    final sub = c.listen(
      tournamentRoundScheduleRealtimeProvider(_tid),
      (_, next) => next.whenData(received.add),
    );
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);

    channel.emit(
      FakeTournamentRemote.roundScheduleChannelKeyFor(_tid),
      _insert(_scheduleRow(status: 'running')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.status, RoundStatus.running);
    expect(received.single.roundNumber, 1);
    expect(received.single.stageNodeId, isNull);
  });

  test('read provider folds the latest row per (round, stageNode)', () async {
    final c = container();
    final snapshots = <Map<({int roundNumber, String? stageNodeId}),
        TournamentRoundScheduleRef>>[];
    final sub = c.listen(
      tournamentRoundScheduleProvider(_tid),
      (_, next) => next.whenData(snapshots.add),
    );
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);

    final key = FakeTournamentRemote.roundScheduleChannelKeyFor(_tid);
    channel.emit(key, _insert(_scheduleRow(roundNumber: 1, status: 'call')));
    await Future<void>.delayed(Duration.zero);
    channel.emit(key, _insert(_scheduleRow(roundNumber: 1, status: 'running')));
    await Future<void>.delayed(Duration.zero);
    channel.emit(key, _insert(_scheduleRow(roundNumber: 2, status: 'call')));
    await Future<void>.delayed(Duration.zero);

    final latest = snapshots.last;
    expect(latest.keys, hasLength(2));
    // Round 1's later 'running' event overwrote the earlier 'call' event.
    expect(
      latest[(roundNumber: 1, stageNodeId: null)]!.status,
      RoundStatus.running,
    );
    expect(
      latest[(roundNumber: 2, stageNodeId: null)]!.status,
      RoundStatus.call,
    );
  });

  test('provider source contains no Timer.periodic poll', () {
    final src = File(
      'lib/features/tournament/application/tournament_realtime_provider.dart',
    ).readAsStringSync();
    expect(src.contains('Timer.periodic'), isFalse);
  });
}
