/// Route paths for the Phase-1 social surface (ADR-0012).
///
/// Note: the `/social/groups` route was removed in Sprint B (Mängel #2.1,
/// R19-F-03, R20-F-01). Teams replace the groups concept per ADR-0018.
/// Datenmigration der `groups`-Tabelle folgt in Sprint C.
abstract final class SocialRoutes {
  static const friends = '/social/friends';
}
