import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/team/application/team_detail_provider.dart';
import 'package:kubb_app/features/team/application/team_list_provider.dart';
import 'package:kubb_app/features/team/data/team_models.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart'
    show realtimeChannelProvider, realtimePollingFallbackProvider;
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Polling cadence used ONLY while the realtime fallback is active
/// (channel ≥60 s errored or kill-switch on). Authenticated concerns poll
/// at 30 s per ADR-0029 §(c) FC-6 — never the old 4 s discovery loop.
const Duration _teamFallbackPollInterval = Duration(seconds: 30);

/// My-teams CDC discovery (ADR-0029 §(e) C3-T2 / Phase P7): replaces the old
/// 4 s `teamListPollingProvider`. A screen watches this while mounted so the
/// "Meine Teams" list reflects a membership change made on another device
/// (e.g. an invitee accepting) automatically — without any periodic poll.
///
/// The per-user channel is `team_memberships:user_id=<uid>` over the app-wide
/// [realtimeChannelProvider] singleton (one WebSocket, multiplexed). On every
/// row-level change it invalidates [teamListProvider]. This provider emits no
/// data; it only drives the invalidation.
///
/// Fallback: when [realtimePollingFallbackProvider] reports the channel
/// unhealthy for this key, a single 30 s re-arming timer takes over. It is
/// gated strictly on that boolean — there is no unconditional `Timer.periodic`.
//
// Riverpod's autoDispose-provider type names are not part of the public API,
// so the lint stays suppressed.
// ignore: specify_nonobvious_property_types
final myTeamsCdcProvider = StreamProvider.autoDispose<void>((ref) {
  final userIdValue = ref.watch(currentUserIdProvider);
  if (userIdValue == null) {
    // Signed out — no subscription, no fallback poll.
    return const Stream<void>.empty();
  }
  final userId = UserId(userIdValue);
  // Channel-key derived exclusively via the kubb_domain builder.
  final channelKey = myTeamsRealtimeChannelKey(userId);

  // CDC path: one row-level change → one list invalidation.
  final channel = ref.watch(realtimeChannelProvider);
  final cdcSub = channel
      .subscribe(
        table: 'team_memberships',
        filterColumn: 'user_id',
        filterValue: userIdValue,
      )
      .listen((_) => ref.invalidate(teamListProvider));

  // Fallback path: only poll while the gate says the channel is down. A
  // self-rearming one-shot Timer (NOT Timer.periodic) gives the 30 s cadence,
  // cleanly stopped the moment the channel recovers.
  Timer? fallbackTimer;
  void armFallback() {
    fallbackTimer = Timer(_teamFallbackPollInterval, () {
      ref.invalidate(teamListProvider);
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

/// Team-detail CDC discovery (ADR-0029 §(e) C3-T2 / Phase P7): replaces the old
/// 4 s `teamDetailPollingProvider`. A detail screen watches this for its team
/// so a change another member made on the server (roster, guests, dissolve)
/// shows up without a manual refresh.
///
/// The per-team channel is `team_memberships:team_id=<tid>` over the app-wide
/// [realtimeChannelProvider] singleton. On every row-level change it
/// invalidates [teamDetailProvider] for that team. Emits no data.
///
/// Fallback identical to [myTeamsCdcProvider]: gated, self-rearming 30 s timer.
// Riverpod's family-provider type names are not part of the public API, so the
// lint stays suppressed.
// ignore: specify_nonobvious_property_types
final teamDetailCdcProvider =
    StreamProvider.autoDispose.family<void, TeamId>((ref, teamId) {
  // Channel-key derived exclusively via the kubb_domain builder.
  final channelKey = teamRealtimeChannelKey(teamId);

  // CDC path: one row-level change → one detail invalidation.
  final channel = ref.watch(realtimeChannelProvider);
  final cdcSub = channel
      .subscribe(
        table: 'team_memberships',
        filterColumn: 'team_id',
        filterValue: teamId.value,
      )
      .listen((_) => ref.invalidate(teamDetailProvider(teamId)));

  // Fallback path: gated, self-rearming one-shot Timer (NOT Timer.periodic).
  Timer? fallbackTimer;
  void armFallback() {
    fallbackTimer = Timer(_teamFallbackPollInterval, () {
      ref.invalidate(teamDetailProvider(teamId));
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

/// One pending team invitation joined with its team header, as needed by
/// the invitation screen. The repository's `team_invitations` rows do
/// not carry the team's display name, so we fetch both in one PostgREST
/// call via the foreign-key join syntax exposed by Supabase RLS.
class PendingTeamInvitation {
  const PendingTeamInvitation({
    required this.invitationId,
    required this.team,
    required this.invitedByUserId,
    required this.createdAt,
  });

  final TeamInvitationId invitationId;
  final TeamWire team;
  final String invitedByUserId;
  final DateTime createdAt;
}

/// Stand-in for the M3.1-T10 controller surface: lists the caller's
/// `state = 'pending'` invitations. Once T10 lands this provider becomes
/// the thin shim it always intended to be.
final pendingInvitationsProvider =
    FutureProvider<List<PendingTeamInvitation>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const <PendingTeamInvitation>[];

  final client = Supabase.instance.client;
  // Scope to invitations addressed TO the caller. The RLS read policy also
  // lets pool members (e.g. the inviter) read a team's pending invitations, so
  // without this filter an inviter would see the invites they sent and tapping
  // "accept" would fail with `caller is not the invitee`.
  final rows = await client
      .from('team_invitations')
      .select(
        'id, team_id, invited_by, created_at, '
        'teams!inner(id, display_name, league_membership, created_at, '
        'logo_url, country, dissolved_at)',
      )
      .eq('state', 'pending')
      .eq('invitee_user_id', userId)
      .order('created_at', ascending: false);

  return rows.map<PendingTeamInvitation>((row) {
    final teamRaw = row['teams'] as Map<String, dynamic>;
    final teamJson = <String, dynamic>{
      'team_id': teamRaw['id'],
      'display_name': teamRaw['display_name'],
      'league_membership': teamRaw['league_membership'],
      'created_at': teamRaw['created_at'],
      'logo_url': teamRaw['logo_url'],
      'country': teamRaw['country'],
      'dissolved_at': teamRaw['dissolved_at'],
    };
    return PendingTeamInvitation(
      invitationId: TeamInvitationId(row['id'] as String),
      team: TeamWire.fromJson(teamJson),
      invitedByUserId: row['invited_by'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }).toList(growable: false);
});

/// Whether the league transfer window (Oct–Feb) is currently open, decided by
/// the server clock — so the edit UI can enable/disable the league control
/// without trusting the device time.
final leagueWindowOpenProvider = FutureProvider<bool>((ref) async {
  return ref.read(teamRepositoryProvider).leagueWindowOpen();
});

/// Imperative action surface for the invitation screen. Routes through
/// [TeamRepository] and invalidates [pendingInvitationsProvider] so the
/// list re-renders without a manual pull-to-refresh.
final teamActionsProvider = Provider<TeamActions>(TeamActions.new);

class TeamActions {
  TeamActions(this._ref);
  final Ref _ref;

  Future<void> respondInvitation(
    TeamInvitationId id, {
    required bool accept,
    TeamId? teamId,
  }) async {
    await _ref
        .read(teamRepositoryProvider)
        .respondInvitation(id, accept: accept);
    _ref.invalidate(pendingInvitationsProvider);
    // R19-F-17: an accepted invitation grows the caller's pool roster
    // and adds the team to "Meine Teams". The list/detail caches are
    // FutureProviders driven by `team_get` / `list_my_teams` RPCs, so
    // without an explicit invalidation the user lands on a detail
    // screen that still hides them from the pool until the next cold
    // start. A decline only needs the invitation list refresh.
    if (accept) {
      _ref.invalidate(teamListProvider);
      if (teamId != null) _ref.invalidate(teamDetailProvider(teamId));
    }
  }
}
