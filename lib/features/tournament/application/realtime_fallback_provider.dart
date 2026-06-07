import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// The canonical key builder now lives in kubb_domain. Hide it from the
// barrel import and re-expose it via a thin delegator below so existing
// call-sites keep resolving against this library.
import 'package:kubb_domain/kubb_domain.dart' hide tournamentRealtimeChannelKey;
import 'package:kubb_domain/kubb_domain.dart' as dom
    show tournamentRealtimeChannelKey;

/// How long the channel must remain `errored` before the fallback flips
/// to "polling active". OD-M4-02 Empfehlung A — short blips during a
/// reconnect should not toggle the UI.
const Duration kRealtimeFallbackErroredGrace = Duration(seconds: 60);

/// Channel-key convention used by [RealtimeChannel] adapters for the
/// per-tournament match feed (OD-M4-01).
///
/// Thin re-export alias: the canonical builder now lives in
/// `kubb_domain` (`src/realtime/channel_keys.dart`) so the key derivation
/// stays single-sourced with `SupabaseRealtimeChannel._keyFor`. Kept here so
/// existing call-sites keep compiling; no own string logic remains.
String tournamentRealtimeChannelKey(TournamentId tournamentId) =>
    dom.tournamentRealtimeChannelKey(tournamentId);

/// App-wide CDC transport singleton (ADR-0029 §(c) FC-7). Overridden
/// exactly once at app bootstrap with the production
/// `SupabaseRealtimeChannel(Supabase.instance.client)` (or a fake in
/// tests) so every CDC consumer — `tournamentRemoteProvider`, the Lamport
/// binder, future feeds — multiplexes the SAME adapter instance over the
/// single Supabase WebSocket. A plain (non-`family`, non-`autoDispose`)
/// `Provider<RealtimeChannel>` guarantees one shared instance per
/// `ProviderContainer`; reading it twice returns the `identical()` adapter.
///
/// Stays unimplemented by default so misconfigured containers surface
/// loudly instead of silently swallowing channel state.
//
// TODO(realtime-sync): the broadcast transport (anon spectator topics)
// gets its own `broadcastChannelProvider` singleton over a
// `SupabaseBroadcastChannel` — deliberately NOT added here; it lands with
// FC-4 in phase P2 (see ADR-0029 §(c)).
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

/// Generalised polling-fallback gate. Emits `true` when the realtime channel
/// identified by `channelKey` is unhealthy and the per-concern polling
/// fallback should take over (ADR-0029 §(c) FC-6). OD-M4-02 Empfehlung A:
///
/// - `joined`             → `false` (realtime healthy).
/// - `errored` ≥ 60 s     → `true`  (assume the WebSocket is gone for good).
/// - `joined` after error → `false` (cancel pending flip, polling off).
/// - feature-flag off     → `true`  (always poll).
///
/// This is a **pure boolean gate** — it owns no data source and never starts
/// a `Timer.periodic`. The polling cadence (30 s authenticated, 10 s anon)
/// belongs to the concern-specific poller that watches this gate, NOT here.
/// The channel-key is always built via a `kubb_domain` builder by the caller
/// (never hand-built). Subscribing uses the App-singleton
/// [realtimeChannelProvider] adapter so all concerns multiplex one socket.
///
/// The stream stays open for the lifetime of the listener; the per-channel
/// reference-counting in [RealtimeChannel] handles teardown.
//
// ignore: specify_nonobvious_property_types
final realtimePollingFallbackProvider =
    StreamProvider.autoDispose.family<bool, String>((ref, channelKey) {
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

  final sub = channel.stateStream(channelKey).listen(
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

/// Per-tournament polling-fallback gate. Thin DELEGATOR onto the generalised
/// [realtimePollingFallbackProvider] (ADR-0029 §(c) FC-6) so existing
/// call-sites keep resolving against `family<bool, TournamentId>` unchanged.
/// The channel-key is derived exclusively via the `kubb_domain` builder
/// [tournamentRealtimeChannelKey] — no hand-built string literal.
//
// ignore: specify_nonobvious_property_types
final realtimeFallbackProvider =
    StreamProvider.autoDispose.family<bool, TournamentId>((ref, id) {
  final key = tournamentRealtimeChannelKey(id);
  final controller = StreamController<bool>(sync: true);
  // Mirror the generalised gate's emissions onto the legacy
  // TournamentId-keyed stream. No own state-machine is duplicated.
  ref
    ..listen<AsyncValue<bool>>(
      realtimePollingFallbackProvider(key),
      (previous, next) {
        next.whenData(controller.add);
      },
      fireImmediately: true,
    )
    ..onDispose(() => unawaited(controller.close()));
  return controller.stream;
});
