/// Static, lint-friendly route constants for the Tournament feature.
///
/// Mirrors the pattern used by `MatchRoutes`. Each "section" route is
/// the base path; concrete URLs append ids.
abstract final class TournamentRoutes {
  /// Tournament hub — the BottomNav tab root (P1). Its tiles route to the
  /// browse list, the caller's registrations, the setup wizard and the
  /// stats placeholder.
  static const hub = '/tournament';

  /// Setup wizard for creating a new tournament.
  static const newTournament = '/tournament/new';

  /// Tournament discovery list (P1: moved off the hub root). Static prefix
  /// so it wins over the dynamic `/tournament/:id` detail route.
  static const list = '/tournament/browse';

  /// Caller's own active registrations (P1 Tournament-Hub).
  static const registrations = '/tournament/registrations';

  /// Tournament statistics — placeholder screen for now (P1; full screen
  /// is a later task).
  static const stats = '/tournament/stats';

  /// Past tournaments (P8): every tournament whose final has been entered
  /// and confirmed (`TournamentStatus.finalized`). Static prefix so it
  /// wins over the dynamic `/tournament/:id` detail route.
  static const pastTournaments = '/tournament/past';

  /// Mercenary market (P8, "Söldnermarkt") — Coming-Soon placeholder.
  /// Static prefix so it wins over the dynamic `/tournament/:id` route.
  static const mercenaryMarket = '/tournament/mercenaries';

  /// Single tournament overview. Append `/:id`.
  static const detail = '/tournament';

  /// Edit an existing tournament (P7). Compose via [edit].
  static const editBase = '/tournament';

  /// Setup-wizard EDIT entry-point for [tournamentId].
  static String edit(String tournamentId) => '$editBase/$tournamentId/edit';

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

  /// P6 shoot-out report/confirm screen for one tie group. The group is
  /// addressed by its zero-based start rank (carried in the shoot-out inbox
  /// payload). Compose as `'/tournament/$tournamentId/shootout/$startRank'`.
  static const shootoutBase = '/tournament';

  static String shootout(String tournamentId, int startRank) =>
      '$shootoutBase/$tournamentId/shootout/$startRank';
}
