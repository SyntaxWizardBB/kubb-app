import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/data/match_repository.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart'
    show realtimeChannelProvider;
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

/// Tests for the standalone-1v1 match-detail CDC provider (ADR-0029 §(e)
/// C5-T1 / Phase P7).
///
/// [matchCdcProvider] subscribes to `matches:id=<mid>` (the standalone
/// `public.matches` table, disjoint from `tournament_matches`) and invalidates
/// [matchDetailProvider] on every row change, with a terminal-stop after
/// `finalized`/`voided`. It rides the App-singleton realtime adapter (a
/// [FakeRealtimeChannel]). Polling is only a gated failure-mode (30 s) — there
/// is no 1 s polling timer anymore.
void main() {
  const matchId = 'm-cdc-1';
  final channelKey = matchRealtimeChannelKey(const MatchId(matchId));

  RealtimeChange change() => RealtimeChange(
        eventType: RealtimeEventType.update,
        table: 'matches',
        rowId: matchId,
        newRow: const <String, Object?>{'id': matchId},
        oldRow: const <String, Object?>{},
        receivedAt: DateTime.utc(2026),
      );

  ProviderContainer makeContainer(
    FakeRealtimeChannel channel,
    _RecordingMatchRepository repo,
  ) {
    final container = ProviderContainer(
      overrides: [
        realtimeChannelProvider.overrideWithValue(channel),
        matchRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('(a) a matches:id CDC event invalidates the match detail', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingMatchRepository();
      final container = makeContainer(channel, repo);

      final cdcSub = container.listen<AsyncValue<void>>(
        matchCdcProvider(matchId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      final detailSub = container.listen<AsyncValue<MatchDetail?>>(
        matchDetailProvider(matchId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(detailSub.close);
      async.flushMicrotasks();

      expect(repo.detailCalls, 1, reason: 'initial detail fetch');

      channel.emit(channelKey, change());
      async
        ..elapse(Duration.zero)
        ..flushMicrotasks();
      expect(repo.detailCalls, 2,
          reason: 'CDC event → detail invalidated + re-fetch');

      channel.emit(channelKey, change());
      async
        ..elapse(Duration.zero)
        ..flushMicrotasks();
      expect(repo.detailCalls, 3,
          reason: 'each subsequent event invalidates again');
    });
  });

  test('(b) terminal-stop: after finalized a further event does not invalidate',
      () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingMatchRepository(status: MatchStatus.finalized);
      final container = makeContainer(channel, repo);

      final cdcSub = container.listen<AsyncValue<void>>(
        matchCdcProvider(matchId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      final detailSub = container.listen<AsyncValue<MatchDetail?>>(
        matchDetailProvider(matchId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(detailSub.close);
      async.flushMicrotasks();

      expect(repo.detailCalls, 1, reason: 'initial detail fetch (finalized)');

      channel.emit(channelKey, change());
      async
        ..elapse(Duration.zero)
        ..flushMicrotasks();
      expect(repo.detailCalls, 1,
          reason: 'terminal status → CDC event suppresses invalidation');
    });
  });

  test('(b2) terminal-stop also holds for voided', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingMatchRepository(status: MatchStatus.voided);
      final container = makeContainer(channel, repo);

      final cdcSub = container.listen<AsyncValue<void>>(
        matchCdcProvider(matchId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      final detailSub = container.listen<AsyncValue<MatchDetail?>>(
        matchDetailProvider(matchId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(detailSub.close);
      async.flushMicrotasks();

      expect(repo.detailCalls, 1, reason: 'initial detail fetch (voided)');

      channel.emit(channelKey, change());
      async
        ..elapse(Duration.zero)
        ..flushMicrotasks();
      expect(repo.detailCalls, 1,
          reason: 'voided status → CDC event suppresses invalidation');
    });
  });

  test('(c) no 1 s timer runs — idle time triggers no invalidation', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingMatchRepository();
      final container = makeContainer(channel, repo);

      final cdcSub = container.listen<AsyncValue<void>>(
        matchCdcProvider(matchId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      final detailSub = container.listen<AsyncValue<MatchDetail?>>(
        matchDetailProvider(matchId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(detailSub.close);

      async
        ..flushMicrotasks()
        // Healthy channel (fake joins on subscribe) → fallback off. Let
        // plenty of "seconds" pass: the old 1 s poller fired ~10 times here.
        ..elapse(const Duration(seconds: 10));

      expect(repo.detailCalls, 1,
          reason: 'healthy channel → no periodic detail refresh');
    });
  });

  test('(d) fallback active → a 30 s invalidation runs (not 1 s)', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingMatchRepository();
      final container = makeContainer(channel, repo);

      final cdcSub = container.listen<AsyncValue<void>>(
        matchCdcProvider(matchId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      final detailSub = container.listen<AsyncValue<MatchDetail?>>(
        matchDetailProvider(matchId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(detailSub.close);
      async.flushMicrotasks();
      expect(repo.detailCalls, 1, reason: 'initial fetch');

      // Drive the channel errored long enough for the 60 s grace gate to flip
      // realtimePollingFallbackProvider to true.
      channel.setState(channelKey, RealtimeChannelState.errored);
      async
        ..elapse(const Duration(seconds: 60))
        ..flushMicrotasks()
        // Nothing in the first 29 s after the gate opened — proves the cadence
        // is not the old 1 s loop.
        ..elapse(const Duration(seconds: 29));
      expect(repo.detailCalls, 1,
          reason: 'fallback cadence is 30 s, nothing fires before that');

      async
        ..elapse(const Duration(seconds: 1))
        ..flushMicrotasks();
      expect(repo.detailCalls, 2,
          reason: 'first fallback invalidation at 30 s');

      async
        ..elapse(const Duration(seconds: 30))
        ..flushMicrotasks();
      expect(repo.detailCalls, 3, reason: 'fallback re-arms every 30 s');
    });
  });
}

/// Test double recording every `detail` call. The CDC provider only drives
/// invalidation; the [matchDetailProvider] re-fetch is the observable proof.
class _RecordingMatchRepository implements MatchRepository {
  _RecordingMatchRepository({this.status = MatchStatus.active});

  final MatchStatus status;
  int detailCalls = 0;

  @override
  Future<MatchDetail?> detail(String matchId) async {
    detailCalls++;
    return MatchDetail(
      match: MatchDetailHeader(
        matchId: matchId,
        createdByUserId: null,
        format: MatchFormat.bo1,
        scoring: MatchScoring.points,
        status: status,
        startedAt: DateTime.utc(2026),
        completedAt: null,
        currentRound: 1,
        settings: const <String, dynamic>{},
      ),
      teams: const [],
      participants: const [],
      ownProposal: null,
      auditTail: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
