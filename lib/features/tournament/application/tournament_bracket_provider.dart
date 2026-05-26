import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// KO bracket for one tournament, fetched via `TournamentRemote.getBracket`.
/// The remote composes the bracket server-side from `tournament_matches`
/// (Architektur §3.3 Application). Polled at the screen level via
/// [tournamentBracketPollingProvider] so newly advanced winners surface
/// without manual reloads.
//
// ignore: specify_nonobvious_property_types
final tournamentBracketProvider =
    FutureProvider.family<Bracket, TournamentId>((ref, id) async {
  return ref.read(tournamentRemoteProvider).getBracket(id);
});

/// Side-effect provider keeping the bracket fresh while the KO screen is
/// mounted. 5s cadence per M1 polling spec (mirrors the match-list
/// polling in `tournament_match_providers.dart`).
//
// ignore: specify_nonobvious_property_types
final tournamentBracketPollingProvider =
    Provider.autoDispose.family<void, TournamentId>((ref, id) {
  final timer = Timer.periodic(const Duration(seconds: 5), (_) {
    ref.invalidate(tournamentBracketProvider(id));
  });
  ref.onDispose(timer.cancel);
});
