// ADR-0031 Phase D, Block D3 — tournamentParticipantListRealtimeProvider.
//
// Drives a tournament_participants CDC row through a FakeTournamentRemote
// (subscribing via a shared FakeRealtimeChannel) and asserts:
//  * the realtime provider relays the parsed TournamentParticipant,
//  * each event invalidates tournamentDetailProvider (re-read),
//  * no Timer.periodic poll exists in the provider source (ADR-0029).
//
// Explicit status/checkedIn arguments spell out each emitted event for
// readability even when they match a builder default — intentional.
// ignore_for_file: avoid_redundant_argument_values

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

const _tid = TournamentId('t-checkin');

Map<String, Object?> _participantRow({
  String? checkedInAt = '2026-06-09T08:30:00.000Z',
  String status = 'confirmed',
}) =>
    <String, Object?>{
      'id': 'p-1',
      'tournament_id': _tid.value,
      'user_id': 'u-1',
      'registration_status': status,
      'seed': null,
      'registered_at': '2026-05-24T10:00:00.000Z',
      'responded_at': null,
      'checked_in_at': checkedInAt,
    };

RealtimeChange _insert(Map<String, Object?> row) => RealtimeChange(
      eventType: RealtimeEventType.insert,
      table: 'tournament_participants',
      rowId: row['id']! as String,
      newRow: row,
      oldRow: const <String, Object?>{},
      receivedAt: DateTime.utc(2026, 6, 9, 8),
    );

void main() {
  late FakeRealtimeChannel channel;
  late FakeTournamentRemote remote;

  setUp(() {
    channel = FakeRealtimeChannel();
    remote = FakeTournamentRemote(
      initialUser: const UserId('u'),
      realtime: channel,
    );
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [tournamentRemoteProvider.overrideWithValue(remote)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('relays a parsed participant with checkedInAt', () async {
    final c = container();
    final received = <TournamentParticipant>[];
    final sub = c.listen(
      tournamentParticipantListRealtimeProvider(_tid),
      (_, next) => next.whenData(received.add),
    );
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);

    channel.emit(
      FakeTournamentRemote.participantsChannelKeyFor(_tid),
      _insert(_participantRow(checkedInAt: '2026-06-09T08:30:00.000Z')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.participantId, 'p-1');
    expect(received.single.isCheckedIn, isTrue);
  });

  test('each CDC event invalidates tournamentDetailProvider (re-read)',
      () async {
    final c = container();

    // Keep both the detail read and the realtime stream alive.
    final detailSub =
        c.listen(tournamentDetailProvider(_tid), (_, _) {});
    addTearDown(detailSub.close);
    final rtSub = c.listen(
      tournamentParticipantListRealtimeProvider(_tid),
      (_, _) {},
    );
    addTearDown(rtSub.close);

    await c.read(tournamentDetailProvider(_tid).future);
    expect(remote.detailFetchCount, 1);

    channel.emit(
      FakeTournamentRemote.participantsChannelKeyFor(_tid),
      _insert(_participantRow()),
    );
    await Future<void>.delayed(Duration.zero);

    // Invalidation forces a fresh read on the next watch.
    await c.read(tournamentDetailProvider(_tid).future);
    expect(
      remote.detailFetchCount,
      2,
      reason: 'a participant CDC event must invalidate the detail provider',
    );
  });

  test('provider source contains no Timer.periodic poll', () {
    final src = File(
      'lib/features/tournament/application/tournament_realtime_provider.dart',
    ).readAsStringSync();
    expect(src.contains('Timer.periodic'), isFalse);
  });
}
