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

/// All of the caller's NON-terminal matches in `tournamentId`, ordered by
/// urgency — the "Mein Match" tab of the H3 live view.
///
/// Filter (Plan A3): the caller participates (participant_a OR
/// participant_b) AND the match status is one of {scheduled,
/// awaitingResults, disputed}. Terminal matches (finalized / overridden /
/// voided) and matches without caller involvement are excluded. Unlike
/// [myActiveMatchProvider] this returns the full list (a player can have
/// more than one open match across phases) and also surfaces `disputed`
/// rows so the player can re-confirm a contested score.
///
/// Reuses the realtime match-list stream and the caller's participant ids
/// from [myTournamentRegistrationsProvider] — no new source.
//
// ignore: specify_nonobvious_property_types
final myActiveMatchesProvider = Provider.autoDispose
    .family<AsyncValue<List<TournamentMatchRef>>, TournamentId>((
  ref,
  tournamentId,
) {
  // Keep the realtime channel alive so list invalidations land while the
  // tab is mounted.
  ref.watch(tournamentMatchListRealtimeProvider(tournamentId));

  final regsAsync = ref.watch(myTournamentRegistrationsProvider);
  final matchesAsync = ref.watch(tournamentMatchListProvider(tournamentId));

  return regsAsync.when(
    loading: () => const AsyncValue<List<TournamentMatchRef>>.loading(),
    error: AsyncValue<List<TournamentMatchRef>>.error,
    data: (regs) {
      final myIds = <TournamentParticipantId>{
        for (final r in regs)
          if (r.tournament.tournamentId == tournamentId) r.participantId,
      };
      if (myIds.isEmpty) {
        return const AsyncValue<List<TournamentMatchRef>>.data(
          <TournamentMatchRef>[],
        );
      }

      return matchesAsync.whenData((matches) {
        return matches.where((m) {
          if (!_isNonTerminal(m.status)) return false;
          if (m.participantB == null) return false; // skip BYE
          return myIds.contains(m.participantA) ||
              myIds.contains(m.participantB);
        }).toList()
          ..sort(_byUrgency);
      });
    },
  );
});

bool _isOpen(TournamentMatchStatus s) =>
    s == TournamentMatchStatus.scheduled ||
    s == TournamentMatchStatus.awaitingResults;

/// Plan A3 filter: scheduled / awaitingResults / disputed are the
/// non-terminal states a player can still act on; finalized / overridden /
/// voided are terminal.
bool _isNonTerminal(TournamentMatchStatus s) =>
    s == TournamentMatchStatus.scheduled ||
    s == TournamentMatchStatus.awaitingResults ||
    s == TournamentMatchStatus.disputed;

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
