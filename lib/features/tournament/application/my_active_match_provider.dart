import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// The caller's current/next match in one tournament, with the pitch label
/// and opponent display name resolved for the player-facing "leg los"
/// banner (spec "TournierStart").
@immutable
class MyActiveMatch {
  const MyActiveMatch({
    required this.match,
    required this.pitchLabel,
    required this.opponentName,
  });

  final TournamentMatchRef match;

  /// Human pitch label, e.g. `"3"`. `TournamentMatchRef` carries no
  /// `pitch_number` yet (see live-dashboard provider doc-block), so the
  /// match number within the round is used as the stable stand-in until
  /// the column lands.
  final String pitchLabel;

  /// Opponent's projected display name, or `null` when unresolved (the UI
  /// renders the localized unknown fallback).
  final String? opponentName;
}

/// Selects the caller's most relevant non-terminal match in `tournamentId`:
/// a match the caller participates in that is still `scheduled` or
/// `awaitingResults`. Bye slots (no opponent) are skipped. Returns `null`
/// when the caller is not registered or has no open match.
///
/// Reuses the realtime match-list stream so the banner updates live as the
/// organizer advances the bracket — the same source the live dashboard
/// consumes. The caller's participant id is resolved from
/// [myTournamentRegistrationsProvider].
//
// ignore: specify_nonobvious_property_types
final myActiveMatchProvider = Provider.autoDispose
    .family<AsyncValue<MyActiveMatch?>, TournamentId>((ref, tournamentId) {
  // Keep the realtime channel alive so list invalidations land while the
  // banner is mounted.
  ref.watch(tournamentMatchListRealtimeProvider(tournamentId));

  final regsAsync = ref.watch(myTournamentRegistrationsProvider);
  final matchesAsync = ref.watch(tournamentMatchListProvider(tournamentId));

  return regsAsync.when(
    loading: () => const AsyncValue<MyActiveMatch?>.loading(),
    error: AsyncValue<MyActiveMatch?>.error,
    data: (regs) {
      final myIds = <TournamentParticipantId>{
        for (final r in regs)
          if (r.tournament.tournamentId == tournamentId) r.participantId,
      };
      if (myIds.isEmpty) return const AsyncValue<MyActiveMatch?>.data(null);

      return matchesAsync.whenData((matches) {
        final mine = matches.where((m) {
          if (!_isOpen(m.status)) return false;
          if (m.participantB == null) return false; // skip BYE
          return myIds.contains(m.participantA) ||
              myIds.contains(m.participantB);
        }).toList()
          // Prefer awaitingResults over scheduled, then the earliest round /
          // match number, so the "current" match wins over a later "next".
          ..sort(_byUrgency);

        if (mine.isEmpty) return null;
        final m = mine.first;
        final callerIsA = myIds.contains(m.participantA);
        return MyActiveMatch(
          match: m,
          pitchLabel: m.matchNumberInRound.toString(),
          opponentName: callerIsA
              ? m.participantBDisplayName
              : m.participantADisplayName,
        );
      });
    },
  );
});

bool _isOpen(TournamentMatchStatus s) =>
    s == TournamentMatchStatus.scheduled ||
    s == TournamentMatchStatus.awaitingResults;

int _byUrgency(TournamentMatchRef a, TournamentMatchRef b) {
  final ra = _statusRank(a.status);
  final rb = _statusRank(b.status);
  if (ra != rb) return ra.compareTo(rb);
  if (a.roundNumber != b.roundNumber) {
    return a.roundNumber.compareTo(b.roundNumber);
  }
  return a.matchNumberInRound.compareTo(b.matchNumberInRound);
}

/// `awaitingResults` (a match already underway) outranks `scheduled`.
int _statusRank(TournamentMatchStatus s) =>
    s == TournamentMatchStatus.awaitingResults ? 0 : 1;
