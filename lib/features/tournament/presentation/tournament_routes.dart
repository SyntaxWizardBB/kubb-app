/// Static, lint-friendly route constants for the Tournament feature.
///
/// Mirrors the pattern used by `MatchRoutes`. Each "section" route is
/// the base path; concrete URLs append ids.
abstract final class TournamentRoutes {
  /// Setup wizard for creating a new tournament.
  static const newTournament = '/tournament/new';

  /// Tournament list / discovery. Append nothing.
  static const list = '/tournament';

  /// Single tournament overview. Append `/:id`.
  static const detail = '/tournament';

  /// Match list for a tournament. Append `/:id/matches`.
  static const matches = '/tournament';

  /// Single tournament match (score entry). Compose as
  /// `'$matchBase/$tournamentId/match/$matchId'`.
  static const matchBase = '/tournament';

  /// Final ranking. Compose as `'$standingsBase/$tournamentId/standings'`.
  static const standingsBase = '/tournament';

  /// KO bracket view. Compose as `'$bracketBase/$tournamentId/bracket'`.
  static const bracketBase = '/tournament';

  /// Live organizer dashboard. Compose via [liveDashboard].
  static const liveDashboardBase = '/tournament';

  static String matchesFor(String tournamentId) =>
      '$matches/$tournamentId/matches';

  static String matchDetail(String tournamentId, String matchId) =>
      '$matchBase/$tournamentId/match/$matchId';

  static String conflict(String tournamentId, String matchId) =>
      '$matchBase/$tournamentId/match/$matchId/conflict';

  /// Organizer override entry-point for a disputed match. Compose as
  /// `'$matchBase/$tournamentId/match/$matchId/override'`.
  static String override(String tournamentId, String matchId) =>
      '$matchBase/$tournamentId/match/$matchId/override';

  static String standings(String tournamentId) =>
      '$standingsBase/$tournamentId/standings';

  static String bracket(String tournamentId) =>
      '$bracketBase/$tournamentId/bracket';

  /// Organizer live dashboard for a running tournament (M4.2-T6).
  static String liveDashboard(String tournamentId) =>
      '$liveDashboardBase/$tournamentId/dashboard';
}
