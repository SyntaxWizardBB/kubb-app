import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// How long the channel must remain `errored` before the fallback flips
/// to "polling active". OD-M4-02 Empfehlung A — short blips during a
/// reconnect should not toggle the UI.
const Duration kRealtimeFallbackErroredGrace = Duration(seconds: 60);

/// Channel-key convention used by [RealtimeChannel] adapters for the
/// per-tournament match feed (OD-M4-01). Must match the key derivation
/// inside `SupabaseRealtimeChannel` so the `stateStream` lookup hits the
/// same entry as the active subscription.
String tournamentRealtimeChannelKey(TournamentId tournamentId) =>
    'tournament_matches:tournament_id=${tournamentId.value}';

/// Adapter wiring for the realtime transport. Overridden at app
/// bootstrap with the production `SupabaseRealtimeChannel` (or a fake in
/// tests). Stays unimplemented by default so misconfigured containers
/// surface loudly instead of silently swallowing channel state.
final Provider<RealtimeChannel> realtimeChannelProvider =
    Provider<RealtimeChannel>((ref) {
  throw UnimplementedError(
    'realtimeChannelProvider must be overridden at app bootstrap.',
  );
});

/// Kill-switch for the realtime transport. `false` forces every
/// fallback provider into polling mode regardless of channel state — used
/// for incident response and for the "Live-Modus aus" Spectator default.
final Provider<bool> realtimeEnabledFlagProvider =
    Provider<bool>((ref) => true);

/// Emits `true` when the per-tournament realtime channel is unhealthy and
/// the polling-fallback should take over. OD-M4-02 Empfehlung A:
///
/// - `joined`            → `false` (realtime healthy).
/// - `errored` ≥ 60 s    → `true`  (assume the WebSocket is gone for good).
/// - `joined` after error → `false` (cancel pending flip, polling off).
/// - feature-flag off    → `true`  (always poll).
///
/// The stream stays open for the lifetime of the listener; the per-channel
/// reference-counting in [RealtimeChannel] handles teardown.
//
// ignore: specify_nonobvious_property_types
final realtimeFallbackProvider =
    StreamProvider.autoDispose.family<bool, TournamentId>((ref, id) {
  if (!ref.watch(realtimeEnabledFlagProvider)) {
    return Stream<bool>.value(true);
  }
  final channel = ref.watch(realtimeChannelProvider);
  final controller = StreamController<bool>(sync: true);
  Timer? pendingFlip;
  var lastEmitted = false;

  void emit({required bool polling}) {
    if (polling == lastEmitted) return;
    lastEmitted = polling;
    controller.add(polling);
  }

  final sub = channel.stateStream(tournamentRealtimeChannelKey(id)).listen(
    (state) {
      switch (state) {
        case RealtimeChannelState.errored:
          pendingFlip ??= Timer(kRealtimeFallbackErroredGrace, () {
            pendingFlip = null;
            emit(polling: true);
          });
        case RealtimeChannelState.joined:
          pendingFlip?.cancel();
          pendingFlip = null;
          emit(polling: false);
        case RealtimeChannelState.connecting:
        case RealtimeChannelState.closed:
          // Transient — keep the current polling/realtime decision.
          break;
      }
    },
  );

  controller.add(false);
  ref.onDispose(() {
    pendingFlip?.cancel();
    unawaited(sub.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
});
