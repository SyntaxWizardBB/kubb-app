import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// One row of the live-dashboard payload — a single pitch's current
/// match. `participantNames` is already display-ready (resolved via the
/// tournament's participant roster, falls back to `?` for empty slots
/// or unknown ids). `currentRound` mirrors the consensus-retry counter
/// from the underlying match (1..3, stays put after `finalized`).
@immutable
class PitchStatus {
  const PitchStatus({
    required this.pitchKey,
    required this.matchId,
    required this.participantNames,
    required this.status,
    required this.currentRound,
  });

  /// Stable grouping key — `pitch_number` when the match row carries
  /// one, otherwise the [matchId] value. Lets the dashboard render a
  /// deterministic order even before pitch assignments roll out
  /// (M5+ migration, see `m4-realtime-dashboard-offline/tasks.md` §T4).
  final String pitchKey;
  final TournamentMatchId matchId;
  final List<String> participantNames;
  final TournamentMatchStatus status;
  final int currentRound;
}

/// Aggregated live-dashboard payload for one tournament. `pitches` is
/// ordered by [PitchStatus.pitchKey] so the UI keeps a stable layout
/// across realtime ticks.
@immutable
class LiveDashboardData {
  const LiveDashboardData({required this.pitches});

  final List<PitchStatus> pitches;
}

/// Live-Dashboard-Aggregator (M4.2 §T4).
///
/// Konsumiert [tournamentMatchListRealtimeProvider] und
/// [tournamentBracketRealtimeProvider], damit jede CDC-Update (Match-Row
/// oder Bracket-Advance) den Polling-/Read-Provider invalidiert und der
/// Aggregator den frischen Snapshot per Re-Read materialisiert. Die
/// Streams selbst werden nicht entpackt — die Realtime-Provider
/// invalidieren bereits [tournamentMatchListProvider] (M4.1 §3.5), das
/// hier konsumiert wird.
///
/// Gruppierung: ein `pitch_number` existiert im Domänen-Snapshot noch
/// nicht (TournamentMatchRef trägt keine Spalte). Bis zur Migration in
/// M5+ wird per `matchId` gruppiert, sodass jede laufende Begegnung als
/// eigene Pitch-Karte erscheint. Sobald `pitch_number` ergänzt ist,
/// reicht ein Patch in [_pitchKeyFor].
///
/// Participant-Namen werden über [tournamentDetailProvider] aufgelöst.
/// Solange das Detail noch lädt, liefert das Lookup leere Strings —
/// der konsumierende Screen kann dann einen Skeleton-State zeigen.
//
// ignore: specify_nonobvious_property_types
final tournamentLiveDashboardProvider = Provider.autoDispose
    .family<AsyncValue<LiveDashboardData>, TournamentId>((ref, tournamentId) {
  // Keep the realtime channels alive so list/bracket invalidations land
  // while the dashboard is mounted. The returned snapshots themselves
  // are not needed here.
  ref
    ..watch(tournamentMatchListRealtimeProvider(tournamentId))
    ..watch(tournamentBracketRealtimeProvider(tournamentId));

  final matchesAsync = ref.watch(tournamentMatchListProvider(tournamentId));
  final detailAsync = ref.watch(tournamentDetailProvider(tournamentId));

  return matchesAsync.whenData((matches) {
    final detail = detailAsync.asData?.value;
    final nameById = <String, String>{
      for (final p in detail?.participants ?? const <TournamentParticipant>[])
        p.participantId: p.displayLabel,
    };

    final entries = matches.map((m) => _toPitchStatus(m, nameById)).toList()
      ..sort((a, b) => a.pitchKey.compareTo(b.pitchKey));

    return LiveDashboardData(pitches: entries);
  });
});

PitchStatus _toPitchStatus(
  TournamentMatchRef m,
  Map<String, String> nameById,
) {
  return PitchStatus(
    pitchKey: _pitchKeyFor(m),
    matchId: m.matchId,
    participantNames: <String>[
      _resolveName(m.participantA, nameById),
      _resolveName(m.participantB, nameById),
    ],
    status: m.status,
    currentRound: m.consensusRound,
  );
}

String _pitchKeyFor(TournamentMatchRef m) {
  // `pitch_number` lands on the row in M5+ (see doc-block on the
  // provider). Until then, match-id is the only stable grouping key.
  return m.matchId.value;
}

String _resolveName(
  TournamentParticipantId? id,
  Map<String, String> nameById,
) {
  if (id == null) return '?';
  return nameById[id.value] ?? '?';
}
