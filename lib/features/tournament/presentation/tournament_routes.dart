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

  static String matchesFor(String tournamentId) =>
      '$matches/$tournamentId/matches';

  static String matchDetail(String tournamentId, String matchId) =>
      '$matchBase/$tournamentId/match/$matchId';

  static String conflict(String tournamentId, String matchId) =>
      '$matchBase/$tournamentId/match/$matchId/conflict';

  static String standings(String tournamentId) =>
      '$standingsBase/$tournamentId/standings';
}
