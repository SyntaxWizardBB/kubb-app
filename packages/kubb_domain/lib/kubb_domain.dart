/// Pure-Dart domain model for the Kubb app.
///
/// This library contains no Flutter imports. It defines the rule engine,
/// match aggregate, score event log, tournament structures, and the ports
/// (interfaces) that infrastructure adapters implement.
library;

export 'src/achievements/badge.dart';
export 'src/achievements/badge_catalog.dart';
export 'src/achievements/badge_match_summary.dart';
export 'src/achievements/badge_session_summary.dart';
export 'src/achievements/badge_trigger.dart';
export 'src/match/match_event.dart';
export 'src/match/match_state.dart';
export 'src/ports/match_event_repository.dart';
export 'src/ports/realtime_channel.dart';
export 'src/ports/tournament_remote.dart';
export 'src/profile/profile_visibility.dart';
export 'src/rules/opening_rule.dart';
export 'src/rules/rule_set.dart';
export 'src/season/season_standings.dart';
export 'src/tournament/bracket.dart';
export 'src/tournament/bracket_advance_event.dart';
export 'src/tournament/bracket_layout.dart';
export 'src/tournament/ekc_score.dart';
export 'src/tournament/elo_seeding.dart';
export 'src/tournament/king_outcome.dart';
export 'src/tournament/ko_phase.dart';
export 'src/tournament/league_points_engine.dart';
export 'src/tournament/pairing.dart';
export 'src/tournament/pitch_assignment.dart';
export 'src/tournament/pool.dart';
export 'src/tournament/pool_group_standings.dart';
export 'src/tournament/pool_phase.dart';
export 'src/tournament/roster_slot.dart';
export 'src/tournament/seeding.dart';
export 'src/tournament/standings.dart';
export 'src/tournament/tiebreaker.dart';
export 'src/tournament/tournament_points_award.dart';
export 'src/tournament/tournament_setup.dart';
export 'src/values/ids.dart';
export 'src/values/lamport_clock.dart';
export 'src/values/league_membership.dart';
export 'src/values/realtime_change.dart';
