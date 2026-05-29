import 'package:drift/drift.dart';

/// Local persistence for unlocked badges, per `(userId, badgeId)`.
///
/// The Sprint B Wave 6 foundation shipped an in-memory implementation of
/// the `AchievementsRepository` so the providers and UI could be wired
/// without persistence. Sprint C W4 promotes the store to Drift so an
/// unlock survives an app restart — a requirement that surfaced once the
/// inventory screen started rendering real (non-mock) data.
///
/// Schema notes:
/// * The primary key is the composite `(userId, badgeId)`. Re-recording
///   an already-unlocked pair must be a no-op (idempotent unlock); the
///   composite key lets us push that guarantee down to the database with
///   `insertOnConflictDoNothing`, instead of relying on a read-modify-
///   write race in application code.
/// * [unlockedAt] is stored as an `int` epoch in milliseconds (UTC) for
///   the same reason the inbox cache uses ints: trivially comparable
///   across platforms and immune to drift's `DateTime` encoding quirks.
/// * `sourceSessionId` is nullable because not every badge is bound to
///   a training/match session (e.g. "Saisonteilnehmer" is awarded from
///   a season aggregate, not a single session) — see `BadgeUnlock`.
///
/// The drift row data class is named `CachedBadgeUnlock` so it does not
/// collide with the domain model `BadgeUnlock` in
/// `packages/kubb_domain/lib/src/achievements/badge.dart`. The repository
/// converts between the two.
@DataClassName('CachedBadgeUnlock')
class BadgeUnlocks extends Table {
  TextColumn get userId => text()();
  TextColumn get badgeId => text()();

  /// Epoch milliseconds (UTC). See class doc for rationale.
  IntColumn get unlockedAt => integer()();

  /// Optional session this unlock was awarded from.
  TextColumn get sourceSessionId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, badgeId};
}
