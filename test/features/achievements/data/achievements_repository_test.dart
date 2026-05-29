import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/achievements/data/achievements_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:path/path.dart' as p;

import '../../../_helpers/sqlite_open.dart';

/// Sprint C W4-T1 — coverage for the Drift-backed
/// [DriftAchievementsRepository] and the in-memory test double.
///
/// The persistence assertion uses an on-disk SQLite file (under a
/// `Directory.systemTemp` sandbox) instead of `NativeDatabase.memory()`
/// because the latter is wiped together with its [AppDatabase] handle,
/// which would make "survives a restart" un-testable. Closing the first
/// database and re-opening a fresh handle against the same file mirrors
/// what happens between two app launches.
void main() {
  setUpAll(registerLinuxSqliteOverride);

  group('DriftAchievementsRepository', () {
    late Directory tmpDir;
    late File dbFile;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('kubb_badge_test_');
      dbFile = File(p.join(tmpDir.path, 'kubb.db'));
    });

    tearDown(() async {
      if (tmpDir.existsSync()) {
        await tmpDir.delete(recursive: true);
      }
    });

    AppDatabase openDb() => AppDatabase(NativeDatabase(dbFile));

    test('recordUnlock + listUnlocksFor round-trip returns the unlock',
        () async {
      final db = openDb();
      addTearDown(db.close);
      final repo = DriftAchievementsRepository(db.badgeUnlocksDao);

      final unlock = BadgeUnlock(
        userId: 'user-1',
        badgeId: 'hits_100',
        unlockedAt: DateTime.utc(2026, 5, 28, 9),
        sourceSessionId: 'session-xyz',
      );
      await repo.recordUnlock(unlock);

      final loaded = await repo.listUnlocksFor(const UserId('user-1'));
      expect(loaded, hasLength(1));
      expect(loaded.single.badgeId, 'hits_100');
      expect(loaded.single.unlockedAt, DateTime.utc(2026, 5, 28, 9));
      expect(loaded.single.sourceSessionId, 'session-xyz');
    });

    test('unlock survives a database close + re-open (app-restart proxy)',
        () async {
      final first = openDb();
      final firstRepo = DriftAchievementsRepository(first.badgeUnlocksDao);
      await firstRepo.recordUnlock(
        BadgeUnlock(
          userId: 'user-1',
          badgeId: 'streak_10',
          unlockedAt: DateTime.utc(2026, 5, 28, 10),
        ),
      );
      await first.close();

      final second = openDb();
      addTearDown(second.close);
      final secondRepo = DriftAchievementsRepository(second.badgeUnlocksDao);

      final loaded = await secondRepo.listUnlocksFor(const UserId('user-1'));
      expect(loaded.map((u) => u.badgeId), ['streak_10']);
      expect(loaded.single.unlockedAt, DateTime.utc(2026, 5, 28, 10));
    });

    test('recordUnlock is idempotent — re-unlock preserves original timestamp',
        () async {
      final db = openDb();
      addTearDown(db.close);
      final repo = DriftAchievementsRepository(db.badgeUnlocksDao);

      final original = DateTime.utc(2026, 5, 28, 9);
      await repo.recordUnlock(
        BadgeUnlock(
          userId: 'user-1',
          badgeId: 'hits_100',
          unlockedAt: original,
          sourceSessionId: 'session-original',
        ),
      );

      // Second record with a later timestamp + different session id —
      // both should be dropped on conflict (PK = userId+badgeId), so the
      // row stays at its original values.
      await repo.recordUnlock(
        BadgeUnlock(
          userId: 'user-1',
          badgeId: 'hits_100',
          unlockedAt: DateTime.utc(2026, 6, 1, 12),
          sourceSessionId: 'session-later',
        ),
      );

      final loaded = await repo.listUnlocksFor(const UserId('user-1'));
      expect(loaded, hasLength(1));
      expect(loaded.single.unlockedAt, original);
      expect(loaded.single.sourceSessionId, 'session-original');
    });

    test('watchUnlocksFor emits an update when a new unlock lands', () async {
      final db = openDb();
      addTearDown(db.close);
      final repo = DriftAchievementsRepository(db.badgeUnlocksDao);

      final emissions = <List<BadgeUnlock>>[];
      final sub = repo
          .watchUnlocksFor(const UserId('user-1'))
          .listen(emissions.add);
      addTearDown(sub.cancel);

      // Initial empty snapshot.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(emissions, isNotEmpty);
      expect(emissions.first, isEmpty);

      await repo.recordUnlock(
        BadgeUnlock(
          userId: 'user-1',
          badgeId: 'first_match',
          unlockedAt: DateTime.utc(2026, 5, 28),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last.map((u) => u.badgeId), contains('first_match'));
    });

    test('listUnlocksFor scopes by userId', () async {
      final db = openDb();
      addTearDown(db.close);
      final repo = DriftAchievementsRepository(db.badgeUnlocksDao);

      await repo.recordUnlock(
        BadgeUnlock(
          userId: 'user-1',
          badgeId: 'hits_100',
          unlockedAt: DateTime.utc(2026, 5, 28),
        ),
      );
      await repo.recordUnlock(
        BadgeUnlock(
          userId: 'user-2',
          badgeId: 'streak_10',
          unlockedAt: DateTime.utc(2026, 5, 28),
        ),
      );

      final u1 = await repo.listUnlocksFor(const UserId('user-1'));
      final u2 = await repo.listUnlocksFor(const UserId('user-2'));
      expect(u1.map((u) => u.badgeId), ['hits_100']);
      expect(u2.map((u) => u.badgeId), ['streak_10']);
    });
  });

  group('BadgeUnlocksDao', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('insertOrIgnore preserves the original row on conflict', () async {
      final dao = db.badgeUnlocksDao;
      await dao.recordUnlock(
        const BadgeUnlocksCompanion(
          userId: Value('user-1'),
          badgeId: Value('hits_100'),
          unlockedAt: Value(1000),
          sourceSessionId: Value<String?>('s-orig'),
        ),
      );
      await dao.recordUnlock(
        const BadgeUnlocksCompanion(
          userId: Value('user-1'),
          badgeId: Value('hits_100'),
          unlockedAt: Value(9999),
          sourceSessionId: Value<String?>('s-later'),
        ),
      );

      final rows = await dao.listFor('user-1');
      expect(rows, hasLength(1));
      expect(rows.single.unlockedAt, 1000);
      expect(rows.single.sourceSessionId, 's-orig');
    });
  });

  group('InMemoryAchievementsRepository', () {
    test('record + list round-trips an unlock', () async {
      final repo = InMemoryAchievementsRepository();
      addTearDown(repo.dispose);

      await repo.recordUnlock(
        BadgeUnlock(
          userId: 'user-1',
          badgeId: 'hits_100',
          unlockedAt: DateTime.utc(2026, 5, 28),
        ),
      );

      final loaded = await repo.listUnlocksFor(const UserId('user-1'));
      expect(loaded.single.badgeId, 'hits_100');
    });

    test('re-recording the same pair is a no-op', () async {
      final repo = InMemoryAchievementsRepository();
      addTearDown(repo.dispose);

      final original = DateTime.utc(2026, 5, 28);
      await repo.recordUnlock(
        BadgeUnlock(
          userId: 'user-1',
          badgeId: 'hits_100',
          unlockedAt: original,
        ),
      );
      await repo.recordUnlock(
        BadgeUnlock(
          userId: 'user-1',
          badgeId: 'hits_100',
          unlockedAt: DateTime.utc(2026, 6),
        ),
      );

      final loaded = await repo.listUnlocksFor(const UserId('user-1'));
      expect(loaded, hasLength(1));
      expect(loaded.single.unlockedAt, original);
    });
  });
}
