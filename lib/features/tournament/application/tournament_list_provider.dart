import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Fetches the caller's visible tournaments, optionally filtered by
/// lifecycle status. `null` returns the union of drafts the caller owns
/// plus any non-draft tournament the server exposes to the caller.
// ignore: specify_nonobvious_property_types
final tournamentListProvider =
    FutureProvider.family<List<TournamentSummaryRef>, TournamentStatus?>(
  (ref, statusFilter) async {
    return ref
        .read(tournamentRemoteProvider)
        .listTournaments(statusFilter: statusFilter);
  },
);

/// Full detail payload for one tournament. Null when the caller has no
/// read access on the row (RLS / RPC returns no record).
// ignore: specify_nonobvious_property_types
final tournamentDetailProvider =
    FutureProvider.family<TournamentDetail?, TournamentId>(
  (ref, tournamentId) async {
    return ref.read(tournamentRemoteProvider).getTournamentDetail(tournamentId);
  },
);

/// Open roster slots for a team participant. Backed by the
/// `tournament_roster_list` RPC (T9). Returns the slots in
/// `slot_index` order; closed history rows are excluded server-side.
// ignore: specify_nonobvious_property_types
final tournamentRosterProvider =
    FutureProvider.family<List<RosterSlot>, TournamentParticipantId>(
  (ref, participantId) async {
    return ref.read(tournamentRemoteProvider).getRoster(participantId);
  },
);

/// Side-effect provider: while watched, invalidates the matching list
/// provider every 5 seconds. Mirrors `matchPollingProvider` but the
/// tournament data is significantly less time-sensitive than a live
/// match, so a wider tick keeps the RPC budget reasonable.
// ignore: specify_nonobvious_property_types
final tournamentListPollingProvider =
    Provider.autoDispose.family<void, TournamentStatus?>(
  (ref, statusFilter) {
    final timer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.invalidate(tournamentListProvider(statusFilter));
    });
    ref.onDispose(timer.cancel);
  },
);

/// Side-effect provider: while watched, invalidates the matching detail
/// provider every 5 seconds. Stops invalidating once the tournament
/// reaches a terminal status (`finalized` / `aborted`) — the timer
/// keeps ticking but the no-op preserves bandwidth.
// ignore: specify_nonobvious_property_types
final tournamentDetailPollingProvider =
    Provider.autoDispose.family<void, TournamentId>(
  (ref, tournamentId) {
    final timer = Timer.periodic(const Duration(seconds: 5), (_) {
      final asyncDetail = ref.read(tournamentDetailProvider(tournamentId));
      final status = asyncDetail.maybeWhen<TournamentStatus?>(
        data: (detail) => detail?.tournament.status,
        orElse: () => null,
      );
      if (status == TournamentStatus.finalized ||
          status == TournamentStatus.aborted) {
        return;
      }
      ref.invalidate(tournamentDetailProvider(tournamentId));
    });
    ref.onDispose(timer.cancel);
  },
);
