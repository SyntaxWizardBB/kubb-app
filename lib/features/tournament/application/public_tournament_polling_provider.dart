import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Polling side-effect for the public tournament screen (M4.2-T11).
///
/// Periodically invalidates [tournamentMatchListProvider] every 10s so
/// the public view stays fresh without holding a realtime channel
/// open. Used when `publicLiveModeProvider` is `false`; the live-mode
/// path layers `tournamentMatchListRealtimeProvider` on top instead.
///
/// `autoDispose` so the timer ends when the screen unmounts.
//
// ignore: specify_nonobvious_property_types
final publicTournamentPollingProvider =
    Provider.autoDispose.family<void, TournamentId>((ref, id) {
  final timer = Timer.periodic(const Duration(seconds: 10), (_) {
    ref.invalidate(tournamentMatchListProvider(id));
  });
  ref.onDispose(timer.cancel);
});
