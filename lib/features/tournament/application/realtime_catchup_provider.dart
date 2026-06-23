import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_domain/kubb_domain.dart' hide tournamentRealtimeChannelKey;

/// Guaranteed catch-up refetch on reconnect/resume (Spec §1.2, ADR-0041,
/// W1-T10).
///
/// CDC is forward-only: anything that happened while the per-tournament
/// channel was `errored`/`closed`, or while the app sat in the background,
/// is never replayed. Without a catch-up the critical screens stay stale
/// until the next live event happens to arrive.
///
/// This provider watches the channel-state stream for the tournament and,
/// on every rejoin — a transition from a non-`joined` state back to
/// `joined` — forces a full refetch of the critical fetch-based read
/// providers EXACTLY ONCE (v1 full-refetch; the monotone delta-cursor is
/// the ADR-0041 target form and follows later). Resume is covered for free:
/// the lifecycle controller's `reconnectKeys` re-subscribe drives the
/// channel back to `joined`, which is the same transition (acceptance 5.2);
/// the ≥60 s error window is the explicit errored->joined case (5.3).
///
/// The FIRST `joined` after subscribe is the initial connect, not a rejoin —
/// it must not refetch (the read providers load themselves on first watch).
///
/// PITFALL (ADR-0041): only fetch-based `FutureProvider`s are invalidated.
/// The CDC-fold round-schedule stream is a live accumulator — invalidating
/// it would reset its accumulated round state, so it is deliberately
/// excluded here.
//
// ignore: specify_nonobvious_property_types
final realtimeCatchupProvider = Provider.autoDispose.family<void, TournamentId>(
  (ref, tournamentId) {
    final channel = ref.watch(realtimeChannelProvider);
    final key = tournamentRealtimeChannelKey(tournamentId);

    var seenJoined = false;
    var wasJoined = false;

    void refetchCritical() {
      ref
        ..invalidate(tournamentStandingsProvider(tournamentId))
        ..invalidate(tournamentMatchListProvider(tournamentId))
        ..invalidate(tournamentDetailProvider(tournamentId));
    }

    final sub = channel.stateStream(key).listen((state) {
      final isJoined = state == RealtimeChannelState.joined;
      if (isJoined && !wasJoined) {
        // A rejoin is any non-joined -> joined edge AFTER the first connect.
        if (seenJoined) {
          refetchCritical();
        }
        seenJoined = true;
      }
      wasJoined = isJoined;
    });

    ref.onDispose(() => unawaited(sub.cancel()));
  },
);
