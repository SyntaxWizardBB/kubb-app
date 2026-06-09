import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
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

/// Realtime stream of a tournament's participant list (ADR-0031 Phase D,
/// Block D3). Consumes [TournamentRemote.watchTournamentParticipants] and, on
/// EVERY CDC event (in particular a `checked_in_at` flip from check-in/undo),
/// invalidates [tournamentDetailProvider] so the regular read provider
/// re-reads the fresh participant snapshot including the joined display
/// names — exactly following the pattern of the three match/bracket realtime
/// providers above.
///
/// Subscribes on the first watch; `autoDispose` tears the subscription down
/// after the last listener (refcount in the realtime adapter). NO new polling:
/// the `tournament_participants` CDC already exists (published since
/// `20261236000000`); the push arrives over the existing per-tournament
/// channel (ADR-0029) — no periodic poll timer.
///
/// The stream forwards the raw [TournamentParticipant] snapshots so the
/// check-in UI (D4) can also consume individual events directly.
//
// ignore: specify_nonobvious_property_types
final tournamentParticipantListRealtimeProvider = StreamProvider.autoDispose
    .family<TournamentParticipant, TournamentId>((ref, tournamentId) {
  final remote = ref.watch(tournamentRemoteProvider);
  final stream = remote.watchTournamentParticipants(tournamentId);
  return stream.map((event) {
    ref.invalidate(tournamentDetailProvider(tournamentId));
    return event;
  });
});

/// Read-side snapshot of one tournament's round-schedule rows (ADR-0031
/// Block A1/A3c), keyed by `(roundNumber, stageNodeId)`. Materialised by
/// folding the per-tournament `tournament_round_schedule` CDC stream — there
/// is no list-fetch RPC; the schedule is pushed, never polled. The detail
/// screen picks the row matching the active match's round to drive the
/// server-/pause-corrected countdown.
///
/// `autoDispose`: the underlying CDC subscription (and its realtime channel)
/// is torn down after the last listener via the adapter's refcount.
//
// ignore: specify_nonobvious_property_types
final tournamentRoundScheduleProvider = StreamProvider.autoDispose.family<
    Map<({int roundNumber, String? stageNodeId}), TournamentRoundScheduleRef>,
    TournamentId>((ref, tournamentId) {
  final remote = ref.watch(tournamentRemoteProvider);
  final latest =
      <({int roundNumber, String? stageNodeId}), TournamentRoundScheduleRef>{};
  return remote.watchRoundSchedule(tournamentId).map((row) {
    latest[(roundNumber: row.roundNumber, stageNodeId: row.stageNodeId)] = row;
    // Hand out an unmodifiable copy so listeners can't mutate the fold state.
    return Map.unmodifiable(latest);
  });
});

/// Realtime-Stream der Runden-Schedule eines Turniers (ADR-0031 Block
/// A3c). Konsumiert [TournamentRemote.watchRoundSchedule] und invalidiert
/// bei jedem CDC-Event [tournamentRoundScheduleProvider], damit Konsumenten
/// den frischen Schedule-Snapshot nachziehen — exakt nach dem Muster der
/// drei Match-/Bracket-Realtime-Provider oben. Subscribe bei erstem Watch,
/// `autoDispose`-Teardown nach dem letzten Listener; kein Polling (ADR-0029).
///
/// Der Stream gibt die rohen [TournamentRoundScheduleRef]-Snapshots weiter,
/// sodass UIs Einzelevents auch direkt verbrauchen können.
///
/// Bewusst NICHT vom A3c-Detail-Screen gewatcht: anders als die drei
/// `FutureProvider`-Read-Provider oben ist [tournamentRoundScheduleProvider]
/// selbst ein CDC-Stream-Fold und zieht live nach, ohne einen
/// Invalidierungs-Kick zu brauchen — ein `ref.invalidate` darauf würde den
/// akkumulierten Round-Fold zurücksetzen. Dieser Invalidierungs-Treiber ist
/// daher der dokumentierte Seam für die Phase-B/E-Dashboards, die den
/// Schedule perspektivisch über fetch-basierte Read-Provider lesen und dann
/// diesen Treiber konsumieren.
//
// ignore: specify_nonobvious_property_types
final tournamentRoundScheduleRealtimeProvider = StreamProvider.autoDispose
    .family<TournamentRoundScheduleRef, TournamentId>((ref, tournamentId) {
  final remote = ref.watch(tournamentRemoteProvider);
  final stream = remote.watchRoundSchedule(tournamentId);
  return stream.map((event) {
    ref.invalidate(tournamentRoundScheduleProvider(tournamentId));
    return event;
  });
});
