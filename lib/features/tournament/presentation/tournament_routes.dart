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

  /// Tournament statistics hub (System 4): series overview + head-to-head.
  static const stats = '/tournament/stats';

  /// Detail of one tournament series. The free-text series key/label is
  /// passed via GoRouter `extra` (a `TournamentSeriesSummary`), not the
  /// URL, because the key is arbitrary text. Static prefix so it wins over
  /// the dynamic `/tournament/:id` detail route.
  static const statsSeries = '/tournament/stats/series';

  /// Past tournaments (P8): every tournament whose final has been entered
  /// and confirmed (`TournamentStatus.finalized`). Static prefix so it
  /// wins over the dynamic `/tournament/:id` detail route.
  static const pastTournaments = '/tournament/past';

  /// Mercenary market (P8, "Söldnermarkt") — Coming-Soon placeholder.
  /// Static prefix so it wins over the dynamic `/tournament/:id` route.
  static const mercenaryMarket = '/tournament/mercenaries';

  /// All-time tournament leaderboard (P8-Hub-B2, "Rangliste"). Static
  /// prefix so it wins over the dynamic `/tournament/:id` detail route.
  static const ranking = '/tournament/ranking';

  /// Global tournament-ELO best-list ("ELO-Bestenliste",
  /// `docs/ELO_RATINGS.md` §7). Static prefix so it wins over the dynamic
  /// `/tournament/:id` detail route.
  static const eloLeaderboard = '/tournament/elo';

  /// Stage-graph builder (ADR-0030 §Editor, form-based variant). Static
  /// prefix so it wins over the dynamic `/tournament/:id` detail route.
  static const stageGraph = '/tournament/stage-graph';

  /// Organizer dashboard overview (ADR-0031 Phase B, Block B4) — the
  /// veranstalter cockpit across every administrable tournament. STATIC
  /// prefix on purpose: it MUST be registered BEFORE the dynamic
  /// `/tournament/:id` detail route so that `'dashboard'` is never matched
  /// as a tournament id (`:id == 'dashboard'`).
  static const dashboard = '/tournament/dashboard';

  /// Per-tournament organizer dashboard detail (ADR-0031 Phase B, Block B4):
  /// the round/match list plus the schedule control bar for ONE tournament.
  /// Composes `'/tournament/<id>/dashboard'`. The `:id` segment is concrete,
  /// so this never collides with the static [dashboard] overview above.
  static String dashboardDetail(String tournamentId) =>
      '$detail/$tournamentId/dashboard';

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

  /// CF6 (K19): manual seeding editor for the KO transition. When a
  /// tournament uses `SeedingMode.manual`, the organizer must commit a
  /// seed list here before the KO phase can start. Compose via [seeding].
  static const seedingBase = '/tournament';

  static String seeding(String tournamentId) =>
      '$seedingBase/$tournamentId/seeding';

  /// H3 player-facing 3-tab live view (Mein Match / Uebersicht /
  /// Rangliste). Compose via [live].
  static const liveBase = '/tournament';

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

  /// H3 player-facing live view for a running tournament. Mirrors the
  /// `standings`/`bracket` composer shape: `/tournament/<id>/live`.
  static String live(String tournamentId) => '$liveBase/$tournamentId/live';

  /// P6 shoot-out report/confirm screen for one tie group. The group is
  /// addressed by its zero-based start rank (carried in the shoot-out inbox
  /// payload). Compose as `'/tournament/$tournamentId/shootout/$startRank'`.
  static const shootoutBase = '/tournament';

  static String shootout(String tournamentId, int startRank) =>
      '$shootoutBase/$tournamentId/shootout/$startRank';
}
