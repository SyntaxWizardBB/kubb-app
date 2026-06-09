import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart'
    show realtimeChannelProvider, realtimePollingFallbackProvider;
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

/// Tournaments the caller is actively registered for (P1 Tournament-Hub).
/// Backed by `tournament_list_my_registrations`; the hub's "Angemeldete
/// Turniere" list watches this, and the withdraw action invalidates it to
/// refresh after a self-withdraw.
final myTournamentRegistrationsProvider =
    FutureProvider<List<MyTournamentRegistration>>((ref) async {
  return ref.read(tournamentRemoteProvider).listMyRegistrations();
});

/// The caller's own LIVE tournaments (H1 Tournament-Hub "Live Turniere").
///
/// Derived purely from [myTournamentRegistrationsProvider] — the caller's
/// active registrations intersected with `status == TournamentStatus.live`.
/// Withdrawn registrations are excluded, matching the discovery list screen,
/// so a user who pulled out of a tournament that later goes live is not
/// auto-pushed into its H3 view. No new transport, no `Timer.periodic`
/// polling (ADR-0029): it reuses the existing registrations source, which the
/// CDC discovery layer already refreshes. The hub's "Live Turniere" tile
/// watches this to decide whether to jump straight into the H3 live view,
/// show a picker, or render an empty state.
final myLiveTournamentsProvider =
    FutureProvider<List<TournamentSummaryRef>>((ref) async {
  final regs = await ref.watch(myTournamentRegistrationsProvider.future);
  return regs
      .where((r) => r.status != TournamentParticipantStatus.withdrawn)
      .map((r) => r.tournament)
      .where((t) => t.status == TournamentStatus.live)
      .toList(growable: false);
});

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

/// Polling cadence used ONLY while the realtime fallback is active
/// (channel ≥60 s errored or kill-switch on). Authenticated concerns poll
/// at 30 s per ADR-0029 §(c) FC-6 — never the old 5 s discovery loop.
const Duration _tournamentFallbackPollInterval = Duration(seconds: 30);

/// The tournament-list filters the discovery screens watch. A participant
/// change on another device must refresh both the "Aktuelle Turniere"
/// (`null`) and the "Vergangene Turniere" ([TournamentStatus.finalized])
/// slices, so the CDC provider invalidates exactly these family keys.
const List<TournamentStatus?> _watchedListFilters = <TournamentStatus?>[
  null,
  TournamentStatus.finalized,
];

/// My-tournaments CDC discovery (ADR-0029 §(e) C4-T2 / Phase P7): replaces the
/// old 5 s `tournamentListPollingProvider`. A discovery screen watches this
/// while mounted so the tournament list reflects a registration/withdraw made
/// on another device automatically — without any periodic poll.
///
/// The per-user channel is `tournament_participants:user_id=<uid>` over the
/// app-wide [realtimeChannelProvider] singleton (one WebSocket, multiplexed).
/// On every row-level change it invalidates the watched [tournamentListProvider]
/// filters. This provider emits no data; it only drives the invalidation.
///
/// DOCUMENTED gap (plan §(b.1)): a tournaments status-only transition
/// (`published`/`registration_closed`) with no match/participant write does
/// not raise CDC. The gated 30 s fallback below covers it.
///
/// Fallback: when [realtimePollingFallbackProvider] reports the channel
/// unhealthy for this key, a single 30 s re-arming timer takes over. It is
/// gated strictly on that boolean — there is no unconditional `Timer.periodic`.
//
// Riverpod's autoDispose-provider type names are not part of the public API,
// so the lint stays suppressed.
// ignore: specify_nonobvious_property_types
final tournamentListCdcProvider = StreamProvider.autoDispose<void>((ref) {
  final userIdValue = ref.watch(currentUserIdProvider);
  if (userIdValue == null) {
    // Signed out — no subscription, no fallback poll.
    return const Stream<void>.empty();
  }
  final userId = UserId(userIdValue);
  // Channel-key derived exclusively via the kubb_domain builder.
  final channelKey = myTournamentsRealtimeChannelKey(userId);

  void invalidateLists() {
    for (final filter in _watchedListFilters) {
      ref.invalidate(tournamentListProvider(filter));
    }
  }

  // CDC path: one row-level change → invalidate the watched list filters.
  final channel = ref.watch(realtimeChannelProvider);
  final cdcSub = channel
      .subscribe(
        table: 'tournament_participants',
        filterColumn: 'user_id',
        filterValue: userIdValue,
      )
      .listen((_) => invalidateLists());

  // Fallback path: only poll while the gate says the channel is down. A
  // self-rearming one-shot Timer (NOT Timer.periodic) gives the 30 s cadence,
  // cleanly stopped the moment the channel recovers.
  Timer? fallbackTimer;
  void armFallback() {
    fallbackTimer = Timer(_tournamentFallbackPollInterval, () {
      invalidateLists();
      armFallback();
    });
  }

  final fallbackSub = ref.listen<AsyncValue<bool>>(
    realtimePollingFallbackProvider(channelKey),
    (_, next) {
      final polling = next.maybeWhen(data: (v) => v, orElse: () => false);
      if (polling) {
        if (fallbackTimer == null) armFallback();
      } else {
        fallbackTimer?.cancel();
        fallbackTimer = null;
      }
    },
    fireImmediately: true,
  );

  ref.onDispose(() {
    fallbackTimer?.cancel();
    fallbackSub.close();
    unawaited(cdcSub.cancel());
    unawaited(channel.close(channelKey));
  });

  return const Stream<void>.empty();
});

/// Tournament-detail CDC discovery (ADR-0029 §(e) C4-T3 / Phase P7): replaces
/// the old 5 s `tournamentDetailPollingProvider`. A detail screen watches this
/// for its tournament so match progress entered on another device shows up
/// without a manual refresh.
///
/// The per-tournament channel is `tournament_matches:tournament_id=<tid>` over
/// the app-wide [realtimeChannelProvider] singleton. On every row-level change
/// it invalidates [tournamentDetailProvider] for that tournament. Emits no data.
///
/// TERMINAL-STOP: once the tournament reaches a terminal status
/// (`finalized` / `aborted`, read from [tournamentDetailProvider]) neither the
/// CDC listener nor the fallback invalidate any further — exactly what the old
/// poller's no-op preserved.
///
/// Fallback identical to [tournamentListCdcProvider]: gated, self-rearming 30 s
/// timer. The 30 s fallback also covers the documented status-only-transition
/// gap (plan §(b.1)).
// Riverpod's family-provider type names are not part of the public API, so the
// lint stays suppressed.
// ignore: specify_nonobvious_property_types
final tournamentDetailCdcProvider =
    StreamProvider.autoDispose.family<void, TournamentId>((ref, tournamentId) {
  // Channel-key derived exclusively via the kubb_domain builder.
  final channelKey = tournamentRealtimeChannelKey(tournamentId);

  // Terminal-stop guard: suppress invalidation once the tournament is
  // finalized/aborted, mirroring the retired poller's no-op.
  bool isTerminal() {
    final status = ref.read(tournamentDetailProvider(tournamentId)).maybeWhen(
          data: (detail) => detail?.tournament.status,
          orElse: () => null,
        );
    return status == TournamentStatus.finalized ||
        status == TournamentStatus.aborted;
  }

  void invalidateDetail() {
    if (isTerminal()) return;
    ref.invalidate(tournamentDetailProvider(tournamentId));
  }

  // CDC path: one row-level change → one detail invalidation (unless terminal).
  final channel = ref.watch(realtimeChannelProvider);
  final cdcSub = channel
      .subscribe(
        table: 'tournament_matches',
        filterColumn: 'tournament_id',
        filterValue: tournamentId.value,
      )
      .listen((_) => invalidateDetail());

  // BUG3/Task3: the roster CDC channel. A pure participant registration/
  // withdrawal writes only `tournament_participants` (no `tournament_matches`
  // row), so without this second subscription a watching organizer would not
  // see a new participant until the 30 s fallback poll. The participants table
  // is already in the supabase_realtime publication (migration 20261236) and
  // its SELECT RLS gates on tournament_id, so this filtered subscription is
  // authorised. One roster change → one detail invalidation (unless terminal).
  final participantsSub = channel
      .subscribe(
        table: 'tournament_participants',
        filterColumn: 'tournament_id',
        filterValue: tournamentId.value,
      )
      .listen((_) => invalidateDetail());

  // Fallback path: gated, self-rearming one-shot Timer (NOT Timer.periodic).
  Timer? fallbackTimer;
  void armFallback() {
    fallbackTimer = Timer(_tournamentFallbackPollInterval, () {
      invalidateDetail();
      armFallback();
    });
  }

  final fallbackSub = ref.listen<AsyncValue<bool>>(
    realtimePollingFallbackProvider(channelKey),
    (_, next) {
      final polling = next.maybeWhen(data: (v) => v, orElse: () => false);
      if (polling) {
        if (fallbackTimer == null) armFallback();
      } else {
        fallbackTimer?.cancel();
        fallbackTimer = null;
      }
    },
    fireImmediately: true,
  );

  ref.onDispose(() {
    fallbackTimer?.cancel();
    fallbackSub.close();
    unawaited(cdcSub.cancel());
    unawaited(participantsSub.cancel());
    unawaited(channel.close(channelKey));
  });

  return const Stream<void>.empty();
});
