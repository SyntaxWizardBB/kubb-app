import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/dao/score_submission_outbox_dao.dart';
import 'package:kubb_app/core/data/device_id_provider.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart'
    show realtimeChannelProvider;
import 'package:kubb_domain/kubb_domain.dart';

/// DAO that persists pending score-submission rows. Exposed here so the
/// hydration provider can query `maxCounterFor` without re-instantiating
/// the accessor on every read.
final scoreSubmissionOutboxDaoProvider =
    Provider<ScoreSubmissionOutboxDao>((ref) {
  return ScoreSubmissionOutboxDao(ref.watch(appDatabaseProvider));
});

/// Per-match Lamport clock, hydrated from the local outbox at build-time
/// and — when a tournament context is wired up via
/// [bindLamportClockToRealtime] — synchronised with the server-side
/// `lamport_counter` stream once the realtime channel has joined.
///
/// Hydration rule (M4.3-T4/T8, mitigates R-M4.3-4): the outbox-max is a
/// strict lower bound for the next emitted counter — the server stream
/// can only correct upwards. The first local [LamportClock.tick] after
/// hydration is therefore guaranteed to be `> outboxMax` even if the
/// previous app session crashed mid-submission.
//
// Riverpod's family-provider type names are not part of the public API,
// so we suppress the lint and rely on the generic args for inference.
// ignore: specify_nonobvious_property_types
final lamportClockProvider =
    FutureProvider.family<LamportClock, MatchId>((ref, matchId) async {
  final deviceId = await ref.watch(deviceIdProvider.future);
  final dao = ref.watch(scoreSubmissionOutboxDaoProvider);
  final outboxMax = await dao.maxCounterFor(matchId.value, deviceId);

  final clock = LamportClock(deviceId: DeviceId(deviceId))
    ..hydrateFromOutbox(matchId, DeviceId(deviceId), outboxMax);
  ref.onDispose(clock.dispose);
  return clock;
});

/// Attaches the server-side `lamport_counter` stream to [clock] for the
/// tournament that owns [matchIdValue]. Subscribes to the same per-tournament
/// realtime channel used by the dashboard (`tournament_matches` CDC) and
/// forwards every `newRow['lamport_counter']` value into
/// [LamportClock.observeFromStream], so the clock advances past any
/// counter the server has already issued — including those emitted by
/// other devices while we were offline.
///
/// Separated from [lamportClockProvider] because the provider's key is
/// the bounded-context [MatchId] while the realtime channel is addressed
/// per `TournamentId`. The caller (a screen that already knows both ids)
/// invokes this once when the realtime channel has reported `joined`.
void bindLamportClockToRealtime(
  Ref ref,
  LamportClock clock,
  TournamentId tournamentId,
  String matchIdValue,
) {
  // FC-7 (ADR-0029 §(c)): reuse the app-wide CDC singleton instead of
  // opening a second `SupabaseRealtimeChannel` here — that would break the
  // single-WebSocket / refcount invariant. The channel-key is derived via
  // the `kubb_domain` builder, never hand-built.
  final adapter = ref.read(realtimeChannelProvider);
  final channelKey = tournamentRealtimeChannelKey(tournamentId);
  final serverCounters = adapter
      .subscribe(
        table: 'tournament_matches',
        filterColumn: 'tournament_id',
        filterValue: tournamentId.value,
      )
      .where(
        (change) =>
            change.eventType != RealtimeEventType.delete &&
            change.newRow['id']?.toString() == matchIdValue,
      )
      .map((change) => change.newRow['lamport_counter'])
      .where((value) => value is int)
      .cast<int>();
  clock.observeFromStream(serverCounters);
  ref.onDispose(() => adapter.close(channelKey));
}
