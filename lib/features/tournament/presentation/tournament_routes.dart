/// Route path constants for the tournament feature.
///
/// The actual router wiring (registration with `GoRouter`, redirect
/// rules) lives in M1-W4. These constants are exposed so the wizard and
/// list/detail screens can share a single source of truth for paths.
class TournamentRoutes {
  const TournamentRoutes._();

  /// Setup wizard for creating a new tournament.
  static const String newTournament = '/tournament/new';

  /// Tournament list. Detail pages use `'$list/:id'`.
  static const String list = '/tournament';

  /// Detail route prefix; concatenate with the tournament id to navigate.
  static const String detail = '/tournament';
}
