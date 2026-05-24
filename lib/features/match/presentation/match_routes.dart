/// Static, lint-friendly route constants for the multiplayer Match
/// feature. Centralised so the router, deep-link handlers, and the
/// inbox kind-dispatcher all reference the same strings.
///
/// Each "section" route is the *base* path; concrete URLs append the
/// match id, e.g. `'${MatchRoutes.lobby}/$matchId'`.
abstract final class MatchRoutes {
  /// Configure & start a brand-new match (single-screen wizard).
  static const newMatch = '/match/new';

  /// Pre-game lobby while invitations are pending. Auto-redirects
  /// to [result] once all invitees have accepted (server flips
  /// match.status to `active`, lobby's listener then routes onward).
  /// Append `/:id`.
  static const lobby = '/match/lobby';

  /// Round result entry / re-edit. The single canonical destination
  /// after invite acceptance — both the inviter (via lobby auto-redirect)
  /// and the invitee (via inbox accept) land here. Append `/:id`.
  static const result = '/match/result';

  /// Waiting for the other in-app participants to confirm the round.
  /// Append `/:id`. Renamed from `await` for the same reason.
  static const awaitOthers = '/match/await';

  /// Terminal screen after a match reaches `finalized` or `voided`.
  /// Shows the winner (or an abort message) plus continue actions.
  /// Append `/:id`.
  static const finished = '/match/finished';
}
