/// Pure-Dart domain model for the Kubb app.
///
/// This library contains no Flutter imports. It defines the rule engine,
/// match aggregate, score event log, tournament structures, and the ports
/// (interfaces) that infrastructure adapters implement.
library;

export 'src/match/match_event.dart';
export 'src/match/match_state.dart';
export 'src/ports/match_event_repository.dart';
export 'src/ports/tournament_remote.dart';
export 'src/rules/opening_rule.dart';
export 'src/rules/rule_set.dart';
export 'src/tournament/bracket.dart';
export 'src/tournament/bracket_layout.dart';
export 'src/tournament/ekc_score.dart';
export 'src/tournament/ko_phase.dart';
export 'src/tournament/pairing.dart';
export 'src/tournament/pool.dart';
export 'src/tournament/roster_slot.dart';
export 'src/tournament/seeding.dart';
export 'src/tournament/standings.dart';
export 'src/tournament/tiebreaker.dart';
export 'src/values/ids.dart';
export 'src/values/lamport_clock.dart';
export 'src/values/league_membership.dart';
