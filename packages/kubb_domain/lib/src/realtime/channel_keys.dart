import 'package:kubb_domain/src/ports/realtime_channel.dart';
import 'package:kubb_domain/src/values/ids.dart';

/// Central channel-key / broadcast-topic builders (ADR-0029 §3 key table).
///
/// Keys MUST never be hand-built at call-sites — a typo yields a dead channel
/// that silently never fires. All CDC builders produce the canonical form
/// `<table>:<column>=<value>`, identical to `SupabaseRealtimeChannel._keyFor`
/// and `fakeRealtimeChannelKey`. Broadcast topics use `<domain>_events:<id>`.

// --- CDC channel keys (form: <table>:<column>=<value>) ---------------------

/// Inbox notification spine: the single per-user CDC subscription.
/// `user_inbox_messages:user_id=<uid>`.
String inboxRealtimeChannelKey(UserId userId) =>
    'user_inbox_messages:user_id=${userId.value}';

/// Live membership state of one team. `team_memberships:team_id=<tid>`.
String teamRealtimeChannelKey(TeamId teamId) =>
    'team_memberships:team_id=${teamId.value}';

/// Live row state of one standalone 1v1 match (`public.matches`, disjoint
/// from `tournament_matches`). `matches:id=<mid>`.
String matchRealtimeChannelKey(MatchId matchId) =>
    'matches:id=${matchId.value}';

/// Drives my-teams list invalidation. `team_memberships:user_id=<uid>`.
String myTeamsRealtimeChannelKey(UserId userId) =>
    'team_memberships:user_id=${userId.value}';

/// Drives my-tournaments list invalidation.
/// `tournament_participants:user_id=<uid>`.
String myTournamentsRealtimeChannelKey(UserId userId) =>
    'tournament_participants:user_id=${userId.value}';

/// Friends edge changes. `friend_edges:owner_user_id=<uid>`.
String friendsRealtimeChannelKey(UserId userId) =>
    'friend_edges:owner_user_id=${userId.value}';

/// Per-tournament match feed (existing key, moved here from
/// `lib/features/tournament/application/realtime_fallback_provider.dart`).
/// `tournament_matches:tournament_id=<tid>`.
String tournamentRealtimeChannelKey(TournamentId tournamentId) =>
    'tournament_matches:tournament_id=${tournamentId.value}';

// --- Broadcast topics (form: <domain>_events:<scope_id>) -------------------

/// Anon-spectator per-tournament broadcast topic (rename of the former
/// `publicTournamentRealtimeTopic`). `public_tournament_events:<tid>`.
String tournamentBroadcastTopic(TournamentId tournamentId) =>
    'public_tournament_events:${tournamentId.value}';

/// Deprecated alias for [tournamentBroadcastTopic]. Kept so existing
/// call-sites in `lib/` keep compiling; P0b migrates them.
// ignore: remove_deprecations_in_breaking_versions
@Deprecated('Use tournamentBroadcastTopic instead.')
String publicTournamentRealtimeTopic(TournamentId tournamentId) =>
    tournamentBroadcastTopic(tournamentId);

// --- Criticality mapping (ADR-0041 §2, Spec §2) ----------------------------

/// Table prefixes whose channels carry the critical freshness tier. In v1
/// only the per-tournament match feed qualifies — it drives the active match
/// score, the live standings and the match status/clock (see
/// [tournamentRealtimeChannelKey]). Declared here as a property of the
/// channel-key builder so the tier is single-sourced and never decided ad hoc
/// at the call-site.
const Set<String> _criticalTablePrefixes = {'tournament_matches'};

/// Maps a CDC channel key to its [RealtimeCriticality] tier.
///
/// Critical concerns (the per-tournament match feed) get the guaranteed
/// catch-up, the tighter fallback cadence and the never-silent degraded
/// banner. Everything else — registration/check-in (`tournament_participants`,
/// `my*`), friends, team memberships, the inbox, and any unknown key —
/// defaults to `normal`, so battery wins unless a concern is explicitly
/// promoted here.
RealtimeCriticality criticalityFor(String channelKey) {
  final table = channelKey.split(':').first;
  return _criticalTablePrefixes.contains(table)
      ? RealtimeCriticality.critical
      : RealtimeCriticality.normal;
}
