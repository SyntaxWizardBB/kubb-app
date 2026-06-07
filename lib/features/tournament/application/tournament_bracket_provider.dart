import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Polling cadence used ONLY while the realtime fallback is active
/// (channel ≥60 s errored or kill-switch off). Authenticated tournament
/// concerns poll at 30 s per ADR-0029 §(c) FC-6 — never the old 5 s loop.
/// CDC (`tournamentBracketRealtimeProvider`) is the live source; this
/// cadence only takes over while the channel is unhealthy.
const Duration _tournamentFallbackPollInterval = Duration(seconds: 30);

/// KO bracket for one tournament, fetched via `TournamentRemote.getBracket`.
/// The remote composes the bracket server-side from `tournament_matches`
/// (Architektur §3.3 Application). Kept fresh at the screen level via
/// [tournamentBracketPollingProvider] so newly advanced winners surface
/// without manual reloads.
//
// ignore: specify_nonobvious_property_types
final tournamentBracketProvider =
    FutureProvider.family<Bracket, TournamentId>((ref, id) async {
  return ref.read(tournamentRemoteProvider).getBracket(id);
});

/// Side-effect provider keeping the bracket fresh while the KO screen is
/// mounted. Bracket CDC is the live source (ADR-0029 §(c) FC-6); polling is
/// ONLY a failure-mode. It is gated on [realtimeFallbackProvider]: a single
/// self-rearming 30 s timer runs while the channel is unhealthy (≥60 s
/// errored or kill-switch off) and is cancelled the moment realtime
/// recovers. No unconditional `Timer.periodic`.
//
// ignore: specify_nonobvious_property_types
final tournamentBracketPollingProvider =
    Provider.autoDispose.family<void, TournamentId>((ref, id) {
  Timer? fallbackTimer;
  void armFallback() {
    fallbackTimer = Timer(_tournamentFallbackPollInterval, () {
      ref.invalidate(tournamentBracketProvider(id));
      armFallback();
    });
  }

  final fallbackSub = ref.listen<AsyncValue<bool>>(
    realtimeFallbackProvider(id),
    (_, next) {
      final polling = next.maybeWhen(data: (v) => v, orElse: () => false);
      if (polling) {
        if (fallbackTimer == null) armFallback();
      } else {
        fallbackTimer?.cancel();
        fallbackTimer = null;
      }
    },
    fireImmediately: true,
  );

  ref.onDispose(() {
    fallbackTimer?.cancel();
    fallbackSub.close();
  });
});

/// Per-group standings snapshot for the pool phase, fetched via
/// `TournamentRemote.getPoolStandings`. Returns one entry per group
/// label, each pre-sorted by the tournament's tiebreaker chain
/// (ADR-0019 §3.5). Only meaningful while
/// `matchFormatConfig['pool_phase']` is `true`; callers gate the watch
/// on that flag so empty pre-pool tournaments don't fire the RPC.
//
// ignore: specify_nonobvious_property_types
final tournamentPoolStandingsProvider =
    FutureProvider.family<List<PoolGroupStandings>, TournamentId>(
        (ref, id) async {
  return ref.read(tournamentRemoteProvider).getPoolStandings(id);
});

/// Side-effect provider keeping the pool-standings snapshot fresh while
/// the Gruppen tab is mounted. Like the bracket poller, CDC is the live
/// source and polling is ONLY a failure-mode (ADR-0029 §(c) FC-6): a single
/// self-rearming 30 s timer runs gated on [realtimeFallbackProvider] while
/// the channel is unhealthy, cancelled on recovery. No unconditional
/// `Timer.periodic`.
//
// ignore: specify_nonobvious_property_types
final tournamentPoolStandingsPollingProvider =
    Provider.autoDispose.family<void, TournamentId>((ref, id) {
  Timer? fallbackTimer;
  void armFallback() {
    fallbackTimer = Timer(_tournamentFallbackPollInterval, () {
      ref.invalidate(tournamentPoolStandingsProvider(id));
      armFallback();
    });
  }

  final fallbackSub = ref.listen<AsyncValue<bool>>(
    realtimeFallbackProvider(id),
    (_, next) {
      final polling = next.maybeWhen(data: (v) => v, orElse: () => false);
      if (polling) {
        if (fallbackTimer == null) armFallback();
      } else {
        fallbackTimer?.cancel();
        fallbackTimer = null;
      }
    },
    fireImmediately: true,
  );

  ref.onDispose(() {
    fallbackTimer?.cancel();
    fallbackSub.close();
  });
});
