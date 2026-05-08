/// Static, lint-friendly route constants for the multiplayer Match
/// feature. Centralised so the router, deep-link handlers, and the
/// inbox kind-dispatcher all reference the same strings.
///
/// Each "section" route is the *base* path; concrete URLs append the
/// match id, e.g. `'${MatchRoutes.lobby}/$matchId'`.
abstract final class MatchRoutes {
  /// Configure & start a brand-new match (single-screen wizard).
  static const newMatch = '/match/new';

  /// Pre-game lobby while invitations are pending or being accepted.
  /// Append `/:id`.
  static const lobby = '/match/lobby';

  /// Active play screen — visible while the match is being played
  /// out at the table. Append `/:id`.
  static const active = '/match/active';

  /// Round result entry / re-edit. Append `/:id`. Renamed from
  /// `await` because that's a Dart reserved word.
  static const result = '/match/result';

  /// Waiting for the other in-app participants to confirm the round.
  /// Append `/:id`. Renamed from `await` for the same reason.
  static const awaitOthers = '/match/await';
}
