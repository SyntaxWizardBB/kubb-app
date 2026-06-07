import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/team/application/team_detail_provider.dart';
import 'package:kubb_app/features/team/application/team_list_provider.dart';
import 'package:kubb_app/features/team/application/team_providers.dart';
import 'package:kubb_app/features/team/data/team_models.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

/// Tests for the team-discovery CDC providers (ADR-0029 §(e) C3-T2 / P7).
///
/// [myTeamsCdcProvider] subscribes to `team_memberships:user_id=<uid>` and
/// [teamDetailCdcProvider] to `team_memberships:team_id=<tid>` via the
/// App-singleton realtime adapter (here a [FakeRealtimeChannel]); each
/// invalidates its data provider on every change. Polling is only a gated
/// failure-mode (30 s cadence) — there is no 4 s discovery timer anymore.
void main() {
  const userId = 'user-team-1';
  const teamIdValue = 'team-1';
  const teamId = TeamId(teamIdValue);

  final myTeamsKey = myTeamsRealtimeChannelKey(const UserId(userId));
  final detailKey = teamRealtimeChannelKey(teamId);

  RealtimeChange membershipEvent({
    required String column,
    required String value,
  }) =>
      RealtimeChange(
        eventType: RealtimeEventType.insert,
        table: 'team_memberships',
        rowId: '$teamIdValue/$userId',
        newRow: <String, Object?>{column: value},
        oldRow: const <String, Object?>{},
        receivedAt: DateTime.utc(2026),
      );

  ProviderContainer makeContainer(
    FakeRealtimeChannel channel,
    _RecordingTeamRepository repo, {
    String? signedInAs = userId,
  }) {
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue(signedInAs),
        isAuthenticatedProvider.overrideWithValue(signedInAs != null),
        realtimeChannelProvider.overrideWithValue(channel),
        teamRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('(a) a user_id team_memberships event invalidates teamListProvider', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingTeamRepository();
      final container = makeContainer(channel, repo);

      final cdcSub = container.listen<AsyncValue<void>>(
        myTeamsCdcProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      final listSub = container.listen<AsyncValue<List<TeamWire>>>(
        teamListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listSub.close);
      async.flushMicrotasks();

      expect(repo.listCalls, 1, reason: 'initial list fetch on first watch');

      channel.emit(myTeamsKey, membershipEvent(column: 'user_id', value: userId));
      async
        ..elapse(Duration.zero)
        ..flushMicrotasks();
      expect(repo.listCalls, 2,
          reason: 'one CDC event → teamListProvider invalidated + re-fetch');

      channel.emit(myTeamsKey, membershipEvent(column: 'user_id', value: userId));
      async
        ..elapse(Duration.zero)
        ..flushMicrotasks();
      expect(repo.listCalls, 3,
          reason: 'each subsequent event invalidates again');
    });
  });

  test('(b) a team_id team_memberships event invalidates teamDetailProvider',
      () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingTeamRepository();
      final container = makeContainer(channel, repo);

      final cdcSub = container.listen<AsyncValue<void>>(
        teamDetailCdcProvider(teamId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      final detailSub = container.listen<AsyncValue<Map<String, dynamic>>>(
        teamDetailProvider(teamId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(detailSub.close);
      async.flushMicrotasks();

      expect(repo.getCalls, 1, reason: 'initial detail fetch on first watch');

      channel.emit(
          detailKey, membershipEvent(column: 'team_id', value: teamIdValue));
      async
        ..elapse(Duration.zero)
        ..flushMicrotasks();
      expect(repo.getCalls, 2,
          reason: 'one CDC event → teamDetailProvider invalidated + re-fetch');

      channel.emit(
          detailKey, membershipEvent(column: 'team_id', value: teamIdValue));
      async
        ..elapse(Duration.zero)
        ..flushMicrotasks();
      expect(repo.getCalls, 3,
          reason: 'each subsequent event invalidates again');
    });
  });

  test('(c) no 4 s timer runs — idle time triggers no invalidation', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingTeamRepository();
      final container = makeContainer(channel, repo);

      final listCdc = container.listen<AsyncValue<void>>(
        myTeamsCdcProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listCdc.close);
      final listSub = container.listen<AsyncValue<List<TeamWire>>>(
        teamListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listSub.close);

      final detailCdc = container.listen<AsyncValue<void>>(
        teamDetailCdcProvider(teamId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(detailCdc.close);
      final detailSub = container.listen<AsyncValue<Map<String, dynamic>>>(
        teamDetailProvider(teamId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(detailSub.close);

      async
        ..flushMicrotasks()
        // Healthy channels (fake joins on subscribe) → fallback off.
        // Let plenty of "seconds" pass: the old poller fired ~10 times here.
        ..elapse(const Duration(seconds: 10));

      expect(repo.listCalls, 1,
          reason: 'healthy channel → no periodic list refresh');
      expect(repo.getCalls, 1,
          reason: 'healthy channel → no periodic detail refresh');
    });
  });

  test('(d) fallback active → a 30 s invalidation runs (not 4 s)', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingTeamRepository();
      final container = makeContainer(channel, repo);

      final cdcSub = container.listen<AsyncValue<void>>(
        myTeamsCdcProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      final listSub = container.listen<AsyncValue<List<TeamWire>>>(
        teamListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listSub.close);
      async.flushMicrotasks();
      expect(repo.listCalls, 1, reason: 'initial fetch');

      // Drive the channel errored long enough for the 60 s grace gate to flip
      // realtimePollingFallbackProvider to true.
      channel.setState(myTeamsKey, RealtimeChannelState.errored);
      async
        ..elapse(const Duration(seconds: 60))
        ..flushMicrotasks()
        // No invalidation in the first 29 s after the gate opened — proves the
        // cadence is not the old 4 s loop.
        ..elapse(const Duration(seconds: 29));
      expect(repo.listCalls, 1,
          reason: 'fallback cadence is 30 s, nothing fires before that');

      async
        ..elapse(const Duration(seconds: 1))
        ..flushMicrotasks();
      expect(repo.listCalls, 2, reason: 'first fallback invalidation at 30 s');

      async
        ..elapse(const Duration(seconds: 30))
        ..flushMicrotasks();
      expect(repo.listCalls, 3, reason: 'fallback re-arms every 30 s');
    });
  });

  test('signed out → no subscription and no list invalidation', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingTeamRepository();
      final container = makeContainer(channel, repo, signedInAs: null);

      final cdcSub = container.listen<AsyncValue<void>>(
        myTeamsCdcProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      final listSub = container.listen<AsyncValue<List<TeamWire>>>(
        teamListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listSub.close);
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 90));

      // teamListProvider still fetches once (it has no auth guard), but the CDC
      // provider must not subscribe nor run any fallback poll → no extra fetch.
      expect(repo.listCalls, lessThanOrEqualTo(1),
          reason: 'signed out → no fallback poll, no extra fetch');
    });
  });
}

/// Test double recording every `listMyTeams` / `getTeam` call. The CDC
/// providers only drive invalidation; the data providers' re-fetch is the
/// observable proof.
class _RecordingTeamRepository implements TeamRepository {
  int listCalls = 0;
  int getCalls = 0;

  @override
  Future<List<TeamWire>> listMyTeams() async {
    listCalls++;
    return const <TeamWire>[];
  }

  @override
  Future<Map<String, dynamic>> getTeam(TeamId id) async {
    getCalls++;
    return const <String, dynamic>{'display_name': 'Team'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
