import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/achievements/application/badge_unlock_listener.dart';
import 'package:kubb_app/features/achievements/data/achievements_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Hand-rolled fake so the listener test does not pull in Drift. Mirrors
/// the contract of [InMemoryAchievementsRepository] but with a recorder
/// so assertions can target the exact call sequence.
class _FakeRepo implements AchievementsRepository {
  final List<BadgeUnlock> recorded = <BadgeUnlock>[];
  final Map<String, List<BadgeUnlock>> seeded = <String, List<BadgeUnlock>>{};

  void seed(BadgeUnlock u) {
    seeded.putIfAbsent(u.userId, () => <BadgeUnlock>[]).add(u);
  }

  @override
  Future<List<BadgeUnlock>> listUnlocksFor(UserId user) async {
    return List<BadgeUnlock>.unmodifiable(seeded[user.value] ?? const []);
  }

  @override
  Stream<List<BadgeUnlock>> watchUnlocksFor(UserId user) {
    return Stream<List<BadgeUnlock>>.value(
      List<BadgeUnlock>.unmodifiable(seeded[user.value] ?? const []),
    );
  }

  @override
  Future<void> recordUnlock(BadgeUnlock unlock) async {
    recorded.add(unlock);
    seed(unlock);
  }
}

void main() {
  group('BadgeUnlockListener.evaluateAfterSession', () {
    test('records a new unlock when the trigger matches', () async {
      final repo = _FakeRepo();
      final listener = BadgeUnlockListener(
        repository: repo,
        readCurrentUserId: () => 'user-1',
        now: () => DateTime.utc(2026, 5, 28, 12),
      );

      await listener.evaluateAfterSession(
        const BadgeSessionSummary(
          sourceSessionId: 'session-100',
          context: BadgeTriggerContext(sniperHits: 100),
        ),
      );

      expect(repo.recorded, hasLength(1));
      expect(repo.recorded.single.badgeId, 'hits_100');
      expect(repo.recorded.single.userId, 'user-1');
      expect(repo.recorded.single.sourceSessionId, 'session-100');
      expect(repo.recorded.single.unlockedAt, DateTime.utc(2026, 5, 28, 12));
    });

    test('does not record when no trigger matches', () async {
      final repo = _FakeRepo();
      final listener = BadgeUnlockListener(
        repository: repo,
        readCurrentUserId: () => 'user-1',
      );

      await listener.evaluateAfterSession(
        const BadgeSessionSummary(
          sourceSessionId: 'session-tiny',
          context: BadgeTriggerContext(sniperHits: 1),
        ),
      );

      expect(repo.recorded, isEmpty);
    });

    test('skips badges that are already unlocked for the user', () async {
      final repo = _FakeRepo()
        ..seed(
          BadgeUnlock(
            userId: 'user-1',
            badgeId: 'hits_100',
            unlockedAt: DateTime.utc(2026, 1, 15),
          ),
        );
      final listener = BadgeUnlockListener(
        repository: repo,
        readCurrentUserId: () => 'user-1',
      );

      await listener.evaluateAfterSession(
        const BadgeSessionSummary(
          sourceSessionId: 'session-200',
          context: BadgeTriggerContext(sniperHits: 200),
        ),
      );

      // hits_100 is suppressed; nothing else matches at 200 hits.
      expect(repo.recorded, isEmpty);
    });

    test('signed-out user is a no-op', () async {
      final repo = _FakeRepo();
      final listener = BadgeUnlockListener(
        repository: repo,
        readCurrentUserId: () => null,
      );

      await listener.evaluateAfterSession(
        const BadgeSessionSummary(
          sourceSessionId: 'session-100',
          context: BadgeTriggerContext(sniperHits: 100),
        ),
      );

      expect(repo.recorded, isEmpty);
    });

    test('multiple matching triggers all persist with the same timestamp',
        () async {
      final repo = _FakeRepo();
      final listener = BadgeUnlockListener(
        repository: repo,
        readCurrentUserId: () => 'user-1',
        now: () => DateTime.utc(2026, 5, 28, 12),
      );

      // 1000 sniper hits trips both hits_100 and hits_1000.
      await listener.evaluateAfterSession(
        const BadgeSessionSummary(
          sourceSessionId: 'session-1000',
          context: BadgeTriggerContext(sniperHits: 1000),
        ),
      );

      final ids = repo.recorded.map((u) => u.badgeId).toSet();
      expect(ids, containsAll(<String>['hits_100', 'hits_1000']));
      expect(
        repo.recorded.every(
          (u) => u.unlockedAt == DateTime.utc(2026, 5, 28, 12),
        ),
        isTrue,
      );
    });
  });

  group('BadgeUnlockListener.evaluateAfterMatch', () {
    test('first finalized match unlocks first_match', () async {
      final repo = _FakeRepo();
      final listener = BadgeUnlockListener(
        repository: repo,
        readCurrentUserId: () => 'user-1',
      );

      await listener.evaluateAfterMatch(
        const BadgeMatchSummary(
          sourceMatchId: 'match-A',
          context: BadgeTriggerContext(matchesPlayed: 1),
        ),
      );

      expect(repo.recorded.map((u) => u.badgeId), contains('first_match'));
      expect(repo.recorded.single.sourceSessionId, 'match-A');
    });

    test('non-matching context records nothing', () async {
      final repo = _FakeRepo();
      final listener = BadgeUnlockListener(
        repository: repo,
        readCurrentUserId: () => 'user-1',
      );

      await listener.evaluateAfterMatch(
        const BadgeMatchSummary(
          sourceMatchId: 'match-A',
          context: BadgeTriggerContext(),
        ),
      );

      expect(repo.recorded, isEmpty);
    });
  });
}
