// W1-T11 (Spec §3.1, acceptance 5.6) — participants/check-in fallback poller.
//
// The per-tournament `tournament_participants` CDC drives check-in freshness
// live, but if the channel falls over (≥60 s errored) check-in freshness drops
// to zero — there was no fallback poller for participants the way matches and
// bracket have one. This proves the new poller is gated on the SAME
// realtimeFallbackProvider gate and refetches tournamentDetailProvider (which
// carries the participant + check-in snapshot) on the 30 s fallback cadence,
// with a single self-rearming timer, no unconditional Timer.periodic.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart' hide tournamentRealtimeChannelKey;
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

class _StubRemote implements TournamentRemote {
  final List<String> detailCalls = <String>[];

  @override
  Future<TournamentDetail?> getTournamentDetail(TournamentId id) async {
    detailCalls.add(id.value);
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ProviderContainer _container(
  TournamentRemote remote,
  FakeRealtimeChannel channel,
) {
  final c = ProviderContainer(
    overrides: [
      tournamentRemoteProvider.overrideWithValue(remote),
      realtimeChannelProvider.overrideWithValue(channel),
      realtimeEnabledFlagProvider.overrideWithValue(true),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  const tid = TournamentId('t-participants');
  final key = tournamentRealtimeChannelKey(tid);

  test('joined channel → no participant poll', () {
    fakeAsync((async) {
      final remote = _StubRemote();
      final channel = FakeRealtimeChannel();
      final c = _container(remote, channel);

      final data = c.listen(tournamentDetailProvider(tid), (_, _) {});
      addTearDown(data.close);
      final sub =
          c.listen(tournamentParticipantsPollingProvider(tid), (_, _) {});
      addTearDown(sub.close);
      channel.setState(key, RealtimeChannelState.joined);
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 120))
        ..flushMicrotasks();

      expect(
        remote.detailCalls.length,
        1,
        reason: 'only the initial fetch — healthy realtime, no poll',
      );
    });
  });

  test('errored ≥60 s → check-in refetch at 30 s cadence', () {
    fakeAsync((async) {
      final remote = _StubRemote();
      final channel = FakeRealtimeChannel();
      final c = _container(remote, channel);

      final data = c.listen(tournamentDetailProvider(tid), (_, _) {});
      addTearDown(data.close);
      final sub =
          c.listen(tournamentParticipantsPollingProvider(tid), (_, _) {});
      addTearDown(sub.close);
      async.flushMicrotasks();
      expect(remote.detailCalls.length, 1);

      channel.setState(key, RealtimeChannelState.errored);
      async
        ..elapse(const Duration(seconds: 60))
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 29))
        ..flushMicrotasks();
      expect(remote.detailCalls.length, 1, reason: 'nothing before 30 s');

      async
        ..elapse(const Duration(seconds: 1))
        ..flushMicrotasks();
      expect(remote.detailCalls.length, 2, reason: 'first poll at 30 s');

      async
        ..elapse(const Duration(seconds: 30))
        ..flushMicrotasks();
      expect(
        remote.detailCalls.length,
        3,
        reason: 'self-rearming single timer keeps the 30 s cadence',
      );
    });
  });

  test('recovery to joined cancels the poller', () {
    fakeAsync((async) {
      final remote = _StubRemote();
      final channel = FakeRealtimeChannel();
      final c = _container(remote, channel);

      final data = c.listen(tournamentDetailProvider(tid), (_, _) {});
      addTearDown(data.close);
      final sub =
          c.listen(tournamentParticipantsPollingProvider(tid), (_, _) {});
      addTearDown(sub.close);
      async.flushMicrotasks();

      channel.setState(key, RealtimeChannelState.errored);
      async
        ..elapse(const Duration(seconds: 90))
        ..flushMicrotasks();
      final afterFirstPoll = remote.detailCalls.length;

      channel.setState(key, RealtimeChannelState.joined);
      async
        ..elapse(const Duration(seconds: 120))
        ..flushMicrotasks();
      expect(
        remote.detailCalls.length,
        afterFirstPoll,
        reason: 'no further polls once realtime is healthy again',
      );
    });
  });
}
