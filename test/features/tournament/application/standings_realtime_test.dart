// W1-T07 (Spec §1.1) — tournamentStandingsRealtimeProvider.
//
// A tournament_matches CDC event must invalidate the fetch-based
// tournamentStandingsProvider so the live ranking recomputes from the fresh
// match snapshot, instead of sitting stale until the next manual reload
// (Spec acceptance 5.1). The proof is a re-read: each CDC event forces a
// fresh listMatchesForTournament/getTournamentDetail round-trip.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

const _tid = TournamentId('t-standings');

Map<String, Object?> _matchRow({
  String status = 'finalized',
  int finalScoreA = 12,
  int finalScoreB = 6,
}) =>
    <String, Object?>{
      'id': 'm-1',
      'tournament_id': _tid.value,
      'round_number': 1,
      'match_number_in_round': 1,
      'participant_a': 'p-a',
      'participant_b': 'p-b',
      'status': status,
      'consensus_round': 1,
      'started_at': null,
      'finalized_at': '2026-06-09T08:30:00.000Z',
      'winner_participant': 'p-a',
      'final_score_a': finalScoreA,
      'final_score_b': finalScoreB,
    };

RealtimeChange _update(Map<String, Object?> row) => RealtimeChange(
      eventType: RealtimeEventType.update,
      table: 'tournament_matches',
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

  test('a tournament_matches CDC event invalidates the standings provider',
      () async {
    final c = container();

    final standingsSub =
        c.listen(tournamentStandingsProvider(_tid), (_, _) {});
    addTearDown(standingsSub.close);
    final rtSub = c.listen(
      tournamentStandingsRealtimeProvider(_tid),
      (_, _) {},
    );
    addTearDown(rtSub.close);

    await c.read(tournamentStandingsProvider(_tid).future);
    final before = remote.detailFetchCount;

    channel.emit(
      FakeTournamentRemote.matchesChannelKeyFor(_tid),
      _update(_matchRow()),
    );
    await Future<void>.delayed(Duration.zero);

    await c.read(tournamentStandingsProvider(_tid).future);
    expect(
      remote.detailFetchCount,
      greaterThan(before),
      reason: 'a match CDC event must invalidate the standings provider',
    );
  });

  test('relays the parsed match snapshot on each event', () async {
    final c = container();
    final received = <TournamentMatchRef>[];
    final sub = c.listen(
      tournamentStandingsRealtimeProvider(_tid),
      (_, next) => next.whenData(received.add),
    );
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);

    channel.emit(
      FakeTournamentRemote.matchesChannelKeyFor(_tid),
      _update(_matchRow()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.matchId, const TournamentMatchId('m-1'));
  });

  test('does not invalidate the CDC-fold round-schedule provider', () {
    // Pitfall guard (Spec §1.1 / tasks W1-T08 note): the realtime driver must
    // target only fetch-based FutureProviders. Invalidating the fold provider
    // would reset its accumulated round state.
    final src = File(
      'lib/features/tournament/application/tournament_realtime_provider.dart',
    ).readAsStringSync();
    final standingsBlock = src.substring(
      src.indexOf('tournamentStandingsRealtimeProvider'),
    );
    final nextProvider = standingsBlock.indexOf('final ', 1);
    final body = nextProvider == -1
        ? standingsBlock
        : standingsBlock.substring(0, nextProvider);
    expect(body.contains('tournamentRoundScheduleProvider'), isFalse);
  });
}
