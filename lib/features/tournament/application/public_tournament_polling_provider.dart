import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
// `tournamentRealtimeChannelKey` is re-exported by realtime_fallback_provider
// (thin delegator onto the canonical kubb_domain builder); hide the duplicate
// from the barrel import so the single re-export resolves unambiguously.
import 'package:kubb_domain/kubb_domain.dart' hide tournamentRealtimeChannelKey;

/// Anon fallback polling cadence. Spectators have no CDC (ADR-0026); the
/// anon broadcast topic (`tournamentBroadcastTopic`) is the live source.
/// When that channel is unhealthy (≥60 s errored) OR the kill-switch
/// ("Live-Modus aus" via [realtimeEnabledFlagProvider]) is off, this anon
/// fallback polls at 10 s — NOT the 30 s authenticated cadence.
const Duration _publicFallbackPollInterval = Duration(seconds: 10);

/// Polling side-effect for the public tournament screen (M4.2-T11).
///
/// Broadcast (`public_tournament_realtime`) is the live source; polling is
/// ONLY a failure-mode (ADR-0029 §(c) FC-6). It is gated on
/// [realtimePollingFallbackProvider] keyed via the [tournamentRealtimeChannelKey]
/// builder — which also covers the kill-switch ([realtimeEnabledFlagProvider]
/// off ⇒ poll). A single self-rearming 10 s timer invalidates
/// [tournamentMatchListProvider] while the channel is unhealthy and is
/// cancelled on recovery. No unconditional `Timer.periodic`.
///
/// `autoDispose` so everything tears down when the screen unmounts.
//
// ignore: specify_nonobvious_property_types
final publicTournamentPollingProvider =
    Provider.autoDispose.family<void, TournamentId>((ref, id) {
  final channelKey = tournamentRealtimeChannelKey(id);

  Timer? fallbackTimer;
  void armFallback() {
    fallbackTimer = Timer(_publicFallbackPollInterval, () {
      ref.invalidate(tournamentMatchListProvider(id));
      armFallback();
    });
  }

  final fallbackSub = ref.listen<AsyncValue<bool>>(
    realtimePollingFallbackProvider(channelKey),
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
