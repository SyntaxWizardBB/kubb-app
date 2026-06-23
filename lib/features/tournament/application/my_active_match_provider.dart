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

  /// Human pitch label, e.g. `"3"`. Uses the server-assigned
  /// `TournamentMatchRef.pitchNumber` (projected by `tournament_list_matches`
  /// since 20261317000000); falls back to the match number within the round
  /// when the match carries no assigned pitch (no PitchPlan / older wire row).
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
          pitchLabel: (m.pitchNumber ?? m.matchNumberInRound).toString(),
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

/// One cross-tournament "ongoing match" pick: the per-tournament selection
/// plus the tournament summary, so the Home tile can render tournament
/// context and compose the match-detail route (P5-C, ADR-0032 §7).
@immutable
class MyActiveTournamentMatch {
  const MyActiveTournamentMatch({
    required this.tournament,
    required this.active,
  });

  /// Summary of the tournament the match belongs to.
  final TournamentSummaryRef tournament;

  /// The per-tournament pick from [myActiveMatchProvider].
  final MyActiveMatch active;
}

/// The caller's most urgent open TOURNAMENT match across all registered
/// tournaments — source of the Home-screen "Laufendes Match" tile (P5-C,
/// ADR-0032 §7).
///
/// Pure client-side fold (OE-6): reads [myTournamentRegistrationsProvider]
/// and watches the existing per-tournament [myActiveMatchProvider] for each
/// candidate tournament — no new transport, no polling (ADR-0029); liveness
/// comes from the realtime match-list channel each per-tournament provider
/// already keeps alive. Only tournament matches are considered (the 1vs1
/// `matches` feature is a separate context and stays untouched).
///
/// Candidates are the caller's non-withdrawn registrations in LIVE
/// tournaments — matches only exist between start and finalization, so this
/// keeps the per-tournament fan-out minimal. Urgency follows [_byUrgency]
/// (awaitingResults before scheduled, then earliest round / match number);
/// ties across tournaments break deterministically on the match id. `null`
/// when the caller has no candidate registration or no open match anywhere.
/// Loading/error anywhere propagates, so the tile stays hidden instead of
/// flashing a less urgent match while another source resolves.
//
// ignore: specify_nonobvious_property_types
final myActiveTournamentMatchProvider =
    Provider.autoDispose<AsyncValue<MyActiveTournamentMatch?>>((ref) {
  final regsAsync = ref.watch(myTournamentRegistrationsProvider);

  return regsAsync.when(
    loading: () => const AsyncValue<MyActiveTournamentMatch?>.loading(),
    error: AsyncValue<MyActiveTournamentMatch?>.error,
    data: (regs) {
      // De-duplicate tournaments (a caller can hold more than one
      // registration row per tournament across roster changes).
      final candidates = <String, TournamentSummaryRef>{};
      for (final r in regs) {
        if (r.status == TournamentParticipantStatus.withdrawn) continue;
        if (r.tournament.status != TournamentStatus.live) continue;
        candidates[r.tournament.tournamentId.value] = r.tournament;
      }
      if (candidates.isEmpty) {
        return const AsyncValue<MyActiveTournamentMatch?>.data(null);
      }

      MyActiveTournamentMatch? best;
      var anyLoading = false;
      for (final tournament in candidates.values) {
        final activeAsync =
            ref.watch(myActiveMatchProvider(tournament.tournamentId));
        if (activeAsync is AsyncError<MyActiveMatch?>) {
          return AsyncValue<MyActiveTournamentMatch?>.error(
            activeAsync.error,
            activeAsync.stackTrace,
          );
        }
        if (!activeAsync.hasValue) {
          // First load of this tournament's match list; previous data (kept
          // across realtime invalidations) is reused to avoid flicker.
          anyLoading = true;
          continue;
        }
        final active = activeAsync.value;
        if (active == null) continue;
        final pick = MyActiveTournamentMatch(
          tournament: tournament,
          active: active,
        );
        if (best == null || _byCrossTournamentUrgency(pick, best) < 0) {
          best = pick;
        }
      }
      if (anyLoading) {
        return const AsyncValue<MyActiveTournamentMatch?>.loading();
      }
      return AsyncValue<MyActiveTournamentMatch?>.data(best);
    },
  );
});

/// Same urgency ordering as [_byUrgency]; equal-urgency picks from
/// different tournaments fall back to the lexicographic match id so the
/// fold is deterministic regardless of registration order.
int _byCrossTournamentUrgency(
  MyActiveTournamentMatch a,
  MyActiveTournamentMatch b,
) {
  final byUrgency = _byUrgency(a.active.match, b.active.match);
  if (byUrgency != 0) return byUrgency;
  return a.active.match.matchId.value.compareTo(b.active.match.matchId.value);
}

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
