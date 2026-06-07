import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart'
    show realtimeChannelProvider;
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

/// Tests for the tournament-discovery CDC providers (ADR-0029 §(e)
/// C4-T2 / C4-T3 / Phase P7).
///
/// [tournamentListCdcProvider] subscribes to
/// `tournament_participants:user_id=<uid>` and invalidates the watched
/// [tournamentListProvider] filters; [tournamentDetailCdcProvider] subscribes
/// to `tournament_matches:tournament_id=<tid>` and invalidates
/// [tournamentDetailProvider] (with a terminal-stop after finalized/aborted).
/// Both ride the App-singleton realtime adapter (a [FakeRealtimeChannel]).
/// Polling is only a gated failure-mode (30 s) — there is no 5 s discovery
/// timer anymore.
void main() {
  const userId = 'user-tourney-1';
  const tournamentIdValue = 'tournament-1';
  const tournamentId = TournamentId(tournamentIdValue);

  final listKey = myTournamentsRealtimeChannelKey(const UserId(userId));
  final detailKey = tournamentRealtimeChannelKey(tournamentId);

  RealtimeChange change({
    required String table,
    required String column,
    required String value,
  }) =>
      RealtimeChange(
        eventType: RealtimeEventType.insert,
        table: table,
        rowId: '$tournamentIdValue/$userId',
        newRow: <String, Object?>{column: value},
        oldRow: const <String, Object?>{},
        receivedAt: DateTime.utc(2026),
      );

  ProviderContainer makeContainer(
    FakeRealtimeChannel channel,
    _RecordingTournamentRemote remote, {
    String? signedInAs = userId,
  }) {
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue(signedInAs),
        isAuthenticatedProvider.overrideWithValue(signedInAs != null),
        realtimeChannelProvider.overrideWithValue(channel),
        tournamentRemoteProvider.overrideWithValue(remote),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('(a) a user_id tournament_participants event invalidates the list', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final remote = _RecordingTournamentRemote();
      final container = makeContainer(channel, remote);

      final cdcSub = container.listen<AsyncValue<void>>(
        tournamentListCdcProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      final nullSub = container.listen<AsyncValue<List<TournamentSummaryRef>>>(
        tournamentListProvider(null),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(nullSub.close);
      final finalizedSub =
          container.listen<AsyncValue<List<TournamentSummaryRef>>>(
        tournamentListProvider(TournamentStatus.finalized),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(finalizedSub.close);
      async.flushMicrotasks();

      expect(remote.listCallsFor(null), 1, reason: 'initial null-filter fetch');
      expect(remote.listCallsFor(TournamentStatus.finalized), 1,
          reason: 'initial finalized-filter fetch');

      channel.emit(listKey,
          change(table: 'tournament_participants', column: 'user_id', value: userId));
      async
        ..elapse(Duration.zero)
        ..flushMicrotasks();
      expect(remote.listCallsFor(null), 2,
          reason: 'CDC event → null filter invalidated + re-fetch');
      expect(remote.listCallsFor(TournamentStatus.finalized), 2,
          reason: 'CDC event → finalized filter invalidated + re-fetch');
    });
  });

  test('(b) a tournament_id tournament_matches event invalidates the detail',
      () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final remote = _RecordingTournamentRemote();
      final container = makeContainer(channel, remote);

      final cdcSub = container.listen<AsyncValue<void>>(
        tournamentDetailCdcProvider(tournamentId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      final detailSub = container.listen<AsyncValue<TournamentDetail?>>(
        tournamentDetailProvider(tournamentId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(detailSub.close);
      async.flushMicrotasks();

      expect(remote.detailCalls, 1, reason: 'initial detail fetch');

      channel.emit(detailKey,
          change(table: 'tournament_matches', column: 'tournament_id', value: tournamentIdValue));
      async
        ..elapse(Duration.zero)
        ..flushMicrotasks();
      expect(remote.detailCalls, 2,
          reason: 'CDC event → detail invalidated + re-fetch');

      channel.emit(detailKey,
          change(table: 'tournament_matches', column: 'tournament_id', value: tournamentIdValue));
      async
        ..elapse(Duration.zero)
        ..flushMicrotasks();
      expect(remote.detailCalls, 3,
          reason: 'each subsequent event invalidates again');
    });
  });

  test('(c) terminal-stop: after finalized a further event does not invalidate',
      () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final remote = _RecordingTournamentRemote(status: TournamentStatus.finalized);
      final container = makeContainer(channel, remote);

      final cdcSub = container.listen<AsyncValue<void>>(
        tournamentDetailCdcProvider(tournamentId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      final detailSub = container.listen<AsyncValue<TournamentDetail?>>(
        tournamentDetailProvider(tournamentId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(detailSub.close);
      async.flushMicrotasks();

      expect(remote.detailCalls, 1, reason: 'initial detail fetch (finalized)');

      channel.emit(detailKey,
          change(table: 'tournament_matches', column: 'tournament_id', value: tournamentIdValue));
      async
        ..elapse(Duration.zero)
        ..flushMicrotasks();
      expect(remote.detailCalls, 1,
          reason: 'terminal status → CDC event suppresses invalidation');
    });
  });

  test('(d) fallback active → a 30 s invalidation runs (not 5 s)', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final remote = _RecordingTournamentRemote();
      final container = makeContainer(channel, remote);

      final cdcSub = container.listen<AsyncValue<void>>(
        tournamentListCdcProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      final nullSub = container.listen<AsyncValue<List<TournamentSummaryRef>>>(
        tournamentListProvider(null),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(nullSub.close);
      async.flushMicrotasks();
      expect(remote.listCallsFor(null), 1, reason: 'initial fetch');

      // Drive the channel errored long enough for the 60 s grace gate to flip
      // realtimePollingFallbackProvider to true.
      channel.setState(listKey, RealtimeChannelState.errored);
      async
        ..elapse(const Duration(seconds: 60))
        ..flushMicrotasks()
        // Nothing in the first 29 s after the gate opened — proves the cadence
        // is not the old 5 s loop.
        ..elapse(const Duration(seconds: 29));
      expect(remote.listCallsFor(null), 1,
          reason: 'fallback cadence is 30 s, nothing fires before that');

      async
        ..elapse(const Duration(seconds: 1))
        ..flushMicrotasks();
      expect(remote.listCallsFor(null), 2,
          reason: 'first fallback invalidation at 30 s');

      async
        ..elapse(const Duration(seconds: 30))
        ..flushMicrotasks();
      expect(remote.listCallsFor(null), 3, reason: 'fallback re-arms every 30 s');
    });
  });

  test('(e) no 5 s timer runs — idle time triggers no invalidation', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final remote = _RecordingTournamentRemote();
      final container = makeContainer(channel, remote);

      final listCdc = container.listen<AsyncValue<void>>(
        tournamentListCdcProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listCdc.close);
      final nullSub = container.listen<AsyncValue<List<TournamentSummaryRef>>>(
        tournamentListProvider(null),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(nullSub.close);

      final detailCdc = container.listen<AsyncValue<void>>(
        tournamentDetailCdcProvider(tournamentId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(detailCdc.close);
      final detailSub = container.listen<AsyncValue<TournamentDetail?>>(
        tournamentDetailProvider(tournamentId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(detailSub.close);

      async
        ..flushMicrotasks()
        // Healthy channels (fake joins on subscribe) → fallback off. Let
        // plenty of "seconds" pass: the old poller fired ~2 times here.
        ..elapse(const Duration(seconds: 10));

      expect(remote.listCallsFor(null), 1,
          reason: 'healthy channel → no periodic list refresh');
      expect(remote.detailCalls, 1,
          reason: 'healthy channel → no periodic detail refresh');
    });
  });

  test('signed out → no list subscription and no invalidation', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final remote = _RecordingTournamentRemote();
      final container = makeContainer(channel, remote, signedInAs: null);

      final cdcSub = container.listen<AsyncValue<void>>(
        tournamentListCdcProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 90));

      // No list watch here: the CDC provider must not subscribe nor poll.
      expect(remote.listCallsFor(null), 0,
          reason: 'signed out → no subscription, no fallback poll');
    });
  });
}

/// Test double recording every `listTournaments` / `getTournamentDetail`
/// call. The CDC providers only drive invalidation; the data providers'
/// re-fetch is the observable proof.
class _RecordingTournamentRemote implements TournamentRemote {
  _RecordingTournamentRemote({this.status = TournamentStatus.live});

  final TournamentStatus status;
  final Map<TournamentStatus?, int> _listCalls = <TournamentStatus?, int>{};
  int detailCalls = 0;

  int listCallsFor(TournamentStatus? filter) => _listCalls[filter] ?? 0;

  @override
  Future<List<TournamentSummaryRef>> listTournaments({
    TournamentStatus? statusFilter,
    int limit = 50,
  }) async {
    _listCalls[statusFilter] = (_listCalls[statusFilter] ?? 0) + 1;
    return const <TournamentSummaryRef>[];
  }

  @override
  Future<TournamentDetail?> getTournamentDetail(TournamentId id) async {
    detailCalls++;
    return TournamentDetail(
      tournament: TournamentDetailHeader(
        tournamentId: id.value,
        displayName: 'T',
        createdByUserId: null,
        clubId: null,
        teamSize: 1,
        maxTeamSize: 1,
        minParticipants: 2,
        maxParticipants: 8,
        format: TournamentFormat.roundRobin,
        scoring: TournamentScoring.ekc,
        matchFormatConfig: const <String, Object?>{},
        tiebreakerOrder: const <String>[],
        byePoints: 0,
        forfeitPoints: 0,
        status: status,
        publishedAt: null,
        startedAt: null,
        completedAt: null,
      ),
      participants: const [],
      matches: const [],
      auditTail: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
