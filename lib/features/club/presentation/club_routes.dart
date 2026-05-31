/// Path constants for the club (Verein) feature. Registered in the Home
/// branch of the shell router next to the team routes.
abstract final class ClubRoutes {
  static const list = '/clubs';
  static const create = '/clubs/create';

  /// Detail route template; use [detailFor] to build a concrete path.
  static const detail = '/clubs/:id';

  /// Member-search/invite route template; use [addMemberFor].
  static const addMember = '/clubs/:id/add';

  static String detailFor(String clubId) => '/clubs/$clubId';

  static String addMemberFor(String clubId) => '/clubs/$clubId/add';
}
