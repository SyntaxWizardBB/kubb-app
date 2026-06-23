// W1-T09 (Spec §1.2, acceptance 5.2/5.3) — realtimeCatchupProvider.
//
// CDC is forward-only: anything missed while a channel was `errored` or while
// the app was backgrounded is never replayed. The catch-up provider closes
// that gap by forcing a full refetch of the critical read providers exactly
// once per rejoin (errored/closed -> joined) — neither zero (stale screen)
// nor a refetch storm on every flicker. Resume is covered because the
// lifecycle controller's reconnectKeys re-subscribe drives the channel back
// to `joined`, which is the same transition.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/realtime_catchup_provider.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart' hide tournamentRealtimeChannelKey;
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

const _tid = TournamentId('t-catchup');

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
      overrides: [
        tournamentRemoteProvider.overrideWithValue(remote),
        realtimeChannelProvider.overrideWithValue(channel),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  final key = tournamentRealtimeChannelKey(_tid);

  test('does not refetch on the initial connect', () async {
    final c = container();
    final sub = c.listen(realtimeCatchupProvider(_tid), (_, _) {});
    addTearDown(sub.close);
    final standingsSub =
        c.listen(tournamentStandingsProvider(_tid), (_, _) {});
    addTearDown(standingsSub.close);
    await c.read(tournamentStandingsProvider(_tid).future);
    final base = remote.matchesFetchCount;
    // The first `joined` after subscribe is the initial connect, not a
    // rejoin — it must not trigger a catch-up refetch.
    channel.setState(key, RealtimeChannelState.joined);
    await Future<void>.delayed(Duration.zero);
    await c.read(tournamentStandingsProvider(_tid).future);
    expect(remote.matchesFetchCount, base);
  });

  test('refetches exactly once on a single errored->joined rejoin', () async {
    final c = container();
    final sub = c.listen(realtimeCatchupProvider(_tid), (_, _) {});
    addTearDown(sub.close);
    final standingsSub =
        c.listen(tournamentStandingsProvider(_tid), (_, _) {});
    addTearDown(standingsSub.close);
    await c.read(tournamentStandingsProvider(_tid).future);
    // Establish the initial connect (screen subscribed -> channel joined).
    channel.setState(key, RealtimeChannelState.joined);
    await Future<void>.delayed(Duration.zero);
    await c.read(tournamentStandingsProvider(_tid).future);
    final base = remote.matchesFetchCount;

    channel
      ..setState(key, RealtimeChannelState.errored)
      ..setState(key, RealtimeChannelState.joined);
    await Future<void>.delayed(Duration.zero);
    await c.read(tournamentStandingsProvider(_tid).future);

    expect(
      remote.matchesFetchCount,
      base + 1,
      reason: 'a single rejoin must refetch the critical provider once',
    );
  });

  test('refetches once per rejoin, not once per state event', () async {
    final c = container();
    final sub = c.listen(realtimeCatchupProvider(_tid), (_, _) {});
    addTearDown(sub.close);
    final standingsSub =
        c.listen(tournamentStandingsProvider(_tid), (_, _) {});
    addTearDown(standingsSub.close);
    // Establish the initial connect first.
    channel.setState(key, RealtimeChannelState.joined);
    await Future<void>.delayed(Duration.zero);
    await c.read(tournamentStandingsProvider(_tid).future);
    final base = remote.matchesFetchCount;

    // Flicker the channel through several transitions but with two genuine
    // rejoins (errored -> joined twice). The fold must count rejoins, not
    // raw `joined` events: a duplicate `joined` is no rejoin.
    channel
      ..setState(key, RealtimeChannelState.errored)
      ..setState(key, RealtimeChannelState.joined)
      ..setState(key, RealtimeChannelState.joined); // duplicate, no rejoin
    await Future<void>.delayed(Duration.zero);
    await c.read(tournamentStandingsProvider(_tid).future);
    expect(
      remote.matchesFetchCount,
      base + 1,
      reason: 'first rejoin (and its duplicate joined) is one refetch',
    );

    channel
      ..setState(key, RealtimeChannelState.errored)
      ..setState(key, RealtimeChannelState.connecting)
      ..setState(key, RealtimeChannelState.joined);
    await Future<void>.delayed(Duration.zero);
    await c.read(tournamentStandingsProvider(_tid).future);

    expect(remote.matchesFetchCount, base + 2);
  });

  test('does not target the CDC-fold round-schedule provider', () {
    // PITFALL guard (ADR-0041 / tasks W1-T10 note): invalidating the fold
    // provider would reset its accumulated round state. The catch-up driver
    // must only hit fetch-based FutureProviders.
    final src = File(
      'lib/features/tournament/application/realtime_catchup_provider.dart',
    ).readAsStringSync();
    expect(src.contains('tournamentRoundScheduleProvider'), isFalse);
  });
}
