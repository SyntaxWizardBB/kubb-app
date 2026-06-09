import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';

/// Skew offset between the server clock and the local device clock
/// (ADR-0031 §Uhr). Computed ONCE via a single `app_server_now()` RPC:
///
///   offset = serverNow - DateTime.now().toUtc()
///
/// The timed-runner UI then renders `now = DateTime.now().toUtc() + offset`
/// (see [serverCorrectedNow]) so the per-second countdown ticker stays a
/// pure local rendering loop. This is deliberately a one-shot
/// [FutureProvider] — NOT a stream/timer poll: re-syncing every second would
/// be an ADR-0029 anti-pattern. A fresh sync happens only when this provider
/// is invalidated (app start / reconnect, driven by the lifecycle
/// controller).
final serverClockOffsetProvider = FutureProvider<Duration>((ref) async {
  final remote = ref.watch(tournamentRemoteProvider);
  final serverNow = await remote.fetchServerNow();
  // serverNow is already UTC (the repo normalises it); compare against the
  // local UTC instant captured at the same moment.
  return serverNow.difference(DateTime.now().toUtc());
});

/// Server-corrected "now" for the 1s UI ticker (ADR-0031 §Uhr). Pure helper
/// — adds the once-synced [offset] to the live local UTC clock so the
/// countdown stays skew-free without any further server round-trips:
///
///   now = DateTime.now().toUtc() + offset
DateTime serverCorrectedNow(Duration offset) =>
    DateTime.now().toUtc().add(offset);
