import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// One row of the live-dashboard payload — a single pitch's current
/// match. `participantNames` carries the server-projected display name
/// per side (`null` when the slot has no resolvable display_name — UI
/// renders the localized `tournamentParticipantUnknown` fallback).
/// `currentRound` mirrors the consensus-retry counter from the
/// underlying match (1..3, stays put after `finalized`).
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

  /// Display names for participant A and B (`[a, b]`). Either entry is
  /// `null` when the slot has no projected display_name — the consuming
  /// screen renders the localized `tournamentParticipantUnknown` label.
  final List<String?> participantNames;
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
/// Participant-Namen kommen direkt vom Match-Row aus
/// `tournament_get`/`tournament_match_get`
/// (`participant_{a,b}_display_name`, projiziert per
/// `COALESCE(user_profiles.nickname, teams.display_name)` — siehe
/// Migration `20260601000003`). Der Detour über
/// `tournamentDetailProvider` aus M4.2 ist entfallen.
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

  return matchesAsync.whenData((matches) {
    final entries = matches.map(_toPitchStatus).toList()
      ..sort((a, b) => a.pitchKey.compareTo(b.pitchKey));

    return LiveDashboardData(pitches: entries);
  });
});

PitchStatus _toPitchStatus(TournamentMatchRef m) {
  return PitchStatus(
    pitchKey: _pitchKeyFor(m),
    matchId: m.matchId,
    participantNames: <String?>[
      _resolveName(m.participantA, m.participantADisplayName),
      _resolveName(m.participantB, m.participantBDisplayName),
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

/// Returns the per-side display name from the match row. `null` signals
/// either an empty slot (BYE) or a participant whose server-projected
/// `display_name` is absent; the consuming screen renders the localized
/// `tournamentParticipantUnknown` fallback in both cases.
String? _resolveName(TournamentParticipantId? id, String? displayName) {
  if (id == null) return null;
  final name = displayName?.trim();
  if (name == null || name.isEmpty) return null;
  return name;
}
