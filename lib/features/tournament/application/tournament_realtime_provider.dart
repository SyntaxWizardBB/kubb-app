import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Realtime-Stream der Match-Liste eines Turniers (M4.1 §3.5).
///
/// Konsumiert [TournamentRemote.watchTournamentMatches] und invalidiert
/// bei jedem CDC-Event den Polling-/Read-Provider
/// [tournamentMatchListProvider], damit Konsumenten den neuen Snapshot
/// per Re-Read materialisieren. Der Stream selbst gibt die rohen
/// [TournamentMatchRef]-Snapshots weiter, sodass UIs (z. B. das Live-
/// Dashboard, OD-M4-01) Einzelevents auch direkt verbrauchen können.
///
/// `autoDispose` per Acceptance-Criterion: nach dem letzten Listener
/// wird die Stream-Subscription gecancelt und der Realtime-Channel im
/// Adapter refcount-basiert geschlossen (M4.1-T3/T4).
//
// ignore: specify_nonobvious_property_types
final tournamentMatchListRealtimeProvider = StreamProvider.autoDispose
    .family<TournamentMatchRef, TournamentId>((ref, tournamentId) {
  final remote = ref.watch(tournamentRemoteProvider);
  final stream = remote.watchTournamentMatches(tournamentId);
  return stream.map((event) {
    ref.invalidate(tournamentMatchListProvider(tournamentId));
    return event;
  });
});

/// Realtime-Stream für ein einzelnes Tournament-Match (M4.1 §3.5).
///
/// Subscribed intern auf den Per-Tournament-Channel (OD-M4-01) und
/// filtert clientseitig auf die übergebene [TournamentMatchId] — wie im
/// Port-Doc-Block (M4.1-T5) verbindlich festgehalten. Fremde
/// `matchId`-Events werden verworfen.
///
/// Bei einem passenden Event wird zusätzlich
/// [tournamentMatchDetailProvider] invalidiert, damit der reguläre Read-
/// Provider den frischen Snapshot nachzieht.
///
/// `autoDispose` per Acceptance-Criterion.
//
// ignore: specify_nonobvious_property_types
final tournamentMatchDetailRealtimeProvider = StreamProvider.autoDispose
    .family<TournamentMatchRef, TournamentMatchId>((ref, matchId) {
  final remote = ref.watch(tournamentRemoteProvider);
  final stream = remote.watchMatch(matchId);
  return stream.where((event) => event.matchId == matchId).map((event) {
    ref.invalidate(tournamentMatchDetailProvider(matchId));
    return event;
  });
});

/// Realtime-Stream für Bracket-Advance-Events eines Turniers (M4.1 §3.5).
///
/// Konsumiert [TournamentRemote.watchBracketAdvances] — feuert nur dann,
/// wenn eine KO-Zeile finalisiert und der Sieger in den Eltern-Slot
/// propagiert wurde. Bei jedem Event wird [tournamentBracketProvider]
/// invalidiert, damit das Bracket-Widget den neuen Stand zieht, ohne die
/// volle Match-Liste neu zu fetchen.
///
/// `autoDispose` per Acceptance-Criterion.
//
// ignore: specify_nonobvious_property_types
final tournamentBracketRealtimeProvider = StreamProvider.autoDispose
    .family<BracketAdvanceEvent, TournamentId>((ref, tournamentId) {
  final remote = ref.watch(tournamentRemoteProvider);
  final stream = remote.watchBracketAdvances(tournamentId);
  return stream.map((event) {
    ref.invalidate(tournamentBracketProvider(tournamentId));
    return event;
  });
});
