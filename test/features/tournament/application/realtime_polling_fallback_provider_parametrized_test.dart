import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_domain/kubb_domain.dart' hide tournamentRealtimeChannelKey;
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

/// Test-Klasse A (ADR-0029 §(f), Plan Phase P4) — PARAMETRIZED gate semantics.
///
/// The single boolean gate `realtimePollingFallbackProvider` must behave
/// identically regardless of WHICH channel-key it watches: the key is opaque
/// to the gate. This file drives the full OD-M4-02 Empfehlung A transition
/// matrix over EVERY CDC channel-key family — inbox, friends, team,
/// tournament, match — proving the state machine is key-agnostic and that the
/// kill-switch short-circuits for every family.
///
/// All channel-keys are built EXCLUSIVELY via the kubb_domain builders; no
/// hand-built `<table>:<column>=<value>` literal appears anywhere.
void main() {
  // One representative key per CDC family, each via its kubb_domain builder.
  final cases = <_GateCase>[
    _GateCase('inbox', inboxRealtimeChannelKey(const UserId('u-inbox'))),
    _GateCase('friends', friendsRealtimeChannelKey(const UserId('u-friends'))),
    _GateCase('team', teamRealtimeChannelKey(const TeamId('team-1'))),
    _GateCase(
      'tournament',
      tournamentRealtimeChannelKey(const TournamentId('t-1')),
    ),
    _GateCase('match', matchRealtimeChannelKey(const MatchId('m-1'))),
  ];

  ProviderContainer makeContainer(
    FakeRealtimeChannel channel, {
    bool realtimeEnabled = true,
  }) {
    final container = ProviderContainer(
      overrides: [
        realtimeChannelProvider.overrideWithValue(channel),
        realtimeEnabledFlagProvider.overrideWithValue(realtimeEnabled),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  for (final gateCase in cases) {
    group('gate semantics — ${gateCase.label} key', () {
      test(
          'joined → false; errored+59 s → false; +1 s → true; '
          'reconnect/joined → cancel + false', () {
        fakeAsync((async) {
          final channel = FakeRealtimeChannel();
          final container = makeContainer(channel);
          final emitted = <bool>[];

          container.listen<AsyncValue<bool>>(
            realtimePollingFallbackProvider(gateCase.key),
            (previous, next) => next.whenData(emitted.add),
            fireImmediately: true,
          );
          // Drive the channel into `joined`.
          channel.setState(gateCase.key, RealtimeChannelState.joined);
          async.flushMicrotasks();
          expect(emitted.last, isFalse, reason: 'joined → false');

          // Errored, still inside the 60 s grace window.
          channel.setState(gateCase.key, RealtimeChannelState.errored);
          async.elapse(const Duration(seconds: 59));
          expect(emitted.last, isFalse, reason: 'errored+59 s → still false');

          // Cross the 60 s boundary → flip to polling.
          async.elapse(const Duration(seconds: 1));
          expect(emitted.last, isTrue, reason: 'errored ≥60 s → true');

          // Reconnect → cancel the flip and report healthy again.
          channel.setState(gateCase.key, RealtimeChannelState.joined);
          async.flushMicrotasks();
          expect(emitted.last, isFalse, reason: 'reconnect/joined → false');
        });
      });

      test('flag off → always true regardless of channel state', () {
        fakeAsync((async) {
          final channel = FakeRealtimeChannel();
          final container = makeContainer(channel, realtimeEnabled: false);
          final emitted = <bool>[];

          container.listen<AsyncValue<bool>>(
            realtimePollingFallbackProvider(gateCase.key),
            (previous, next) => next.whenData(emitted.add),
            fireImmediately: true,
          );
          // Even a healthy joined channel must not pull the gate back to false
          // while the kill-switch is engaged — the flag check short-circuits
          // BEFORE the channel is ever watched.
          channel.setState(gateCase.key, RealtimeChannelState.joined);
          async.elapse(const Duration(seconds: 120));
          expect(emitted, isNotEmpty, reason: 'flag off emits immediately');
          expect(emitted, everyElement(isTrue),
              reason: 'flag off → true even with a joined channel');
        });
      });
    });
  }
}

/// One parametrized gate scenario: a human label plus the channel-key built
/// via the corresponding kubb_domain builder.
class _GateCase {
  _GateCase(this.label, this.key);

  final String label;
  final String key;
}
