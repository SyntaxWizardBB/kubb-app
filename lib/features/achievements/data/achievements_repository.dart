import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Read/write surface for badge unlocks.
///
/// The Sprint B Wave 6 foundation ships an in-memory implementation
/// so the providers and UI can be wired and tested without persistence.
/// The Drift-backed implementation lands in Sprint C once the designer
/// has shipped the badge glyphs and the inventory screen is ready.
///
// TODO(sprint-c): replace the in-memory stub with a Drift-backed
// implementation. Suggested schema (matches the [BadgeUnlock] value):
//
//   class BadgeUnlocks extends Table {
//     TextColumn  get userId          => text()();
//     TextColumn  get badgeId         => text()();
//     DateTimeColumn get unlockedAt   => dateTime()();
//     TextColumn  get sourceSessionId => text().nullable()();
//     @override
//     Set<Column> get primaryKey      => {userId, badgeId};
//   }
//
// The repository will then expose a `watchUnlocksFor` stream backed by
// the DAO's `watchAll` query instead of the local broadcast controller.
abstract class AchievementsRepository {
  /// One-shot read of all badges the given user has unlocked.
  Future<List<BadgeUnlock>> listUnlocksFor(UserId user);

  /// Live view used by the inventory screen. Emits once on subscribe
  /// with the current list, then again whenever an unlock is recorded.
  Stream<List<BadgeUnlock>> watchUnlocksFor(UserId user);

  /// Idempotent. Re-recording an existing `(userId, badgeId)` pair is
  /// a no-op (the original [BadgeUnlock.unlockedAt] is preserved).
  Future<void> recordUnlock(BadgeUnlock unlock);
}

/// In-memory implementation used until the Drift table lands. Safe to
/// instantiate in tests and as a placeholder dependency in providers.
class InMemoryAchievementsRepository implements AchievementsRepository {
  InMemoryAchievementsRepository();

  final Map<String, List<BadgeUnlock>> _byUser = <String, List<BadgeUnlock>>{};
  final Map<String, StreamController<List<BadgeUnlock>>> _controllers =
      <String, StreamController<List<BadgeUnlock>>>{};

  @override
  Future<List<BadgeUnlock>> listUnlocksFor(UserId user) async {
    return List<BadgeUnlock>.unmodifiable(_byUser[user.value] ?? const []);
  }

  @override
  Stream<List<BadgeUnlock>> watchUnlocksFor(UserId user) {
    final controller = _controllers.putIfAbsent(
      user.value,
      StreamController<List<BadgeUnlock>>.broadcast,
    );
    // Emit current snapshot asynchronously so listeners receive it.
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(
          List<BadgeUnlock>.unmodifiable(_byUser[user.value] ?? const []),
        );
      }
    });
    return controller.stream;
  }

  @override
  Future<void> recordUnlock(BadgeUnlock unlock) async {
    final list = _byUser.putIfAbsent(unlock.userId, () => <BadgeUnlock>[]);
    final exists = list.any((u) => u.badgeId == unlock.badgeId);
    if (exists) return;
    list.add(unlock);
    final controller = _controllers[unlock.userId];
    if (controller != null && !controller.isClosed) {
      controller.add(List<BadgeUnlock>.unmodifiable(list));
    }
  }

  /// Releases broadcast controllers — call from tests or DI teardown.
  Future<void> dispose() async {
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }
}

/// DI handle. Defaults to the in-memory stub; Sprint C will swap in
/// the Drift-backed implementation via an override in `app.dart`.
final achievementsRepositoryProvider = Provider<AchievementsRepository>((ref) {
  final repo = InMemoryAchievementsRepository();
  ref.onDispose(repo.dispose);
  return repo;
});
