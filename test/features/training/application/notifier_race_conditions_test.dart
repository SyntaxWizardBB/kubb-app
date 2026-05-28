// Race-condition specs for the training notifiers and repository.
//
// These tests are intentionally RED with the current implementation
// (W2-T7, refs R3-F-04 + R4-F-01..03 + R5-F-01..02). They pin the four
// concurrency holes that W2-T8 is going to close:
//
//   1. Sniper double-tap on a hit/miss/heli pad: parallel `_append` calls
//      capture the same snapshot of `state`, both write to the DB, but
//      both clobber state with the same `_bump(snapshot, +1)` — DB ends
//      up with two rows while the UI only counts one.
//   2. Sniper double-tap on the start button: `startSession` reads
//      `activeForUser` then deletes, then inserts. Two concurrent calls
//      both see "no active" and both insert -> two active rows for the
//      same player.
//   3. `TrainingRepository.startSession` is not transactional. If the
//      insert fails after the delete went through, the previously
//      running session is gone without a replacement.
//   4. Finisseur parallel `advance()` calls capture the same
//      `currentIndex` and both write a stick row at that index — the
//      stick events table grows two entries for one logical stock.
//
// When W2-T8 lands the mutex + transactional path, every test below
// should flip to green untouched.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/data/dao/session_dao.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/features/training/application/active_finisseur_notifier.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';
import 'package:kubb_app/features/training/application/active_session_notifier.dart';
import 'package:kubb_app/features/training/data/training_repository.dart';

import '../../../_helpers/sqlite_open.dart';

class _FakeAppSettingsNotifier extends AppSettingsNotifier {
  _FakeAppSettingsNotifier(this._initial);

  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;
}

Future<void> _seedPlayer(AppDatabase db, String id) {
  return db.playerDao.insert(
    PlayersCompanion(
      id: Value(id),
      name: const Value('Lukas'),
      deviceId: Value('device-$id'),
      createdAt: Value(DateTime.utc(2026, 5, 2)),
    ),
  );
}

ProviderContainer _container({
  required AppDatabase db,
  AppSettings settings = const AppSettings(),
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      appSettingsProvider
          .overrideWith(() => _FakeAppSettingsNotifier(settings)),
    ],
  );
}

/// SessionDao stub that delegates every call to a real DAO but fails on
/// the first `insert` after a `deleteById`. Used to simulate a crash
/// between the delete-stale-active and insert-fresh-active steps of
/// [TrainingRepository.startSession] so we can pin the missing
/// transactional boundary.
class _CrashAfterDeleteSessionDao extends SessionDao {
  _CrashAfterDeleteSessionDao(super.attachedDatabase);

  bool _deleted = false;
  bool _exploded = false;

  @override
  Future<void> deleteById(String id) async {
    _deleted = true;
    await super.deleteById(id);
  }

  @override
  Future<void> insert(SessionsCompanion companion) async {
    if (_deleted && !_exploded) {
      _exploded = true;
      throw StateError('simulated crash between delete and insert');
    }
    return super.insert(companion);
  }
}

void main() {
  const playerId = 'p1';
  late AppDatabase db;
  late ProviderContainer container;

  setUpAll(registerLinuxSqliteOverride);

  setUp(() async {
    db = await openTestDatabase();
    await _seedPlayer(db, playerId);
    container = _container(db: db);
    addTearDown(container.dispose);
  });

  tearDown(() async {
    await db.close();
  });

  // ---------------------------------------------------------------------
  // R4-F-01: Sniper double-tap on a hit pad must count twice.
  //
  // Given an active sniper session with zero hits,
  // When two `recordHit()` calls are fired in parallel (the user double-
  //   taps the pad inside the 10ms debounce gap),
  // Then both the DB and the in-memory state report two hits — no event
  //   gets silently dropped.
  //
  // Currently RED: `_append` captures `state.value` before awaiting the
  // DB write, so both calls bump from `hits=0` to `hits=1` and the second
  // increment is lost from the UI state (the DB still gets two rows,
  // which means the DB count and the UI count diverge).
  // ---------------------------------------------------------------------
  test(
    'double-tap recordHit within 10ms counts twice in state and in DB',
    () async {
      final notifier = container.read(activeSessionProvider.notifier);
      await notifier.startSession(playerId: playerId, distance: 8);
      final sessionId =
          container.read(activeSessionProvider).requireValue!.sessionId;

      // Fire both taps concurrently — no awaits between them so the
      // second call enters `_withActive` while the first is still
      // suspended on `appendEvent`.
      await Future.wait<void>([
        notifier.recordHit(),
        notifier.recordHit(),
      ]);

      final state = container.read(activeSessionProvider).requireValue!;
      final hitsInDb =
          await db.sessionEventDao.countByKind(sessionId, 'hit');

      expect(hitsInDb, 2, reason: 'both hits should be persisted');
      expect(
        state.hits,
        2,
        reason: 'state must reflect both hits, not silently drop one',
      );
    },
  );

  // ---------------------------------------------------------------------
  // R4-F-02: Sniper double-tap on the start button creates exactly one
  // active session (no ghost stub left behind).
  //
  // Given no active session,
  // When two `startSession(...)` calls are fired in parallel (impatient
  //   user double-taps "Start"),
  // Then the DB holds exactly one active row for the player and no
  //   orphaned/ghost session rows linger.
  //
  // Currently RED: both calls observe `activeForUser == null`, skip the
  // delete branch, and each inserts a new active row.
  // ---------------------------------------------------------------------
  test(
    'double-tap startSession leaves exactly one active session in the DB',
    () async {
      final notifier = container.read(activeSessionProvider.notifier);

      await Future.wait<void>([
        notifier.startSession(playerId: playerId, distance: 8),
        notifier.startSession(playerId: playerId, distance: 8),
      ]);

      final allForPlayer = await (db.select(db.sessions)
            ..where((s) => s.playerId.equals(playerId)))
          .get();
      final active =
          allForPlayer.where((s) => s.status == 'active').toList();

      expect(
        active,
        hasLength(1),
        reason:
            'a second start-tap must not insert a parallel ghost session',
      );
      expect(
        allForPlayer,
        hasLength(1),
        reason: 'no orphaned stubs should be left behind',
      );
    },
  );

  // ---------------------------------------------------------------------
  // R3-F-04: `TrainingRepository.startSession` must be transactional so
  // a crash between the stale-delete and the fresh-insert keeps the
  // prior session row alive instead of leaving the player with nothing.
  //
  // Given a prior active session in the DB,
  // When `startSession` is called against a DAO that fails on insert
  //   (simulating a crash after the delete already went through),
  // Then the throw propagates AND the prior session row is still
  //   present, so the player can resume.
  //
  // Currently RED: the implementation deletes first, then inserts. A
  // failing insert leaves the table empty — the prior session is lost.
  // ---------------------------------------------------------------------
  test(
    'startSession rolls back the stale-delete when the insert fails',
    () async {
      // Seed a prior active session directly so we control its id.
      const priorId = 'prior-active';
      await db.sessionDao.insert(
        SessionsCompanion(
          id: const Value(priorId),
          playerId: const Value(playerId),
          kind: const Value('sniper'),
          mode: const Value('sniper'),
          distanceMeters: const Value(8),
          status: const Value('active'),
          startedAt: Value(DateTime.utc(2026, 5, 2, 10)),
        ),
      );

      final faultyDao = _CrashAfterDeleteSessionDao(db);
      final repo = TrainingRepository(
        sessionDao: faultyDao,
        eventDao: db.sessionEventDao,
      );

      Object? thrown;
      try {
        await repo.startSession(playerId: playerId, distance: 6);
      } on Object catch (e) {
        thrown = e;
      }

      expect(
        thrown,
        isNotNull,
        reason: 'the simulated insert failure must surface to the caller',
      );

      final stillThere = await db.sessionDao.getById(priorId);
      expect(
        stillThere,
        isNotNull,
        reason:
            'a transactional startSession must restore the prior active '
            'row when the follow-up insert fails',
      );
      expect(stillThere!.status, 'active');
    },
  );

  // ---------------------------------------------------------------------
  // R5-F-01..02: Finisseur parallel `advance()` calls must not collide
  // on the same `stickIndex`.
  //
  // Given an active finisseur session sitting at stick 0,
  // When two `advance()` calls fire in parallel (impatient double-tap on
  //   "Stock abschliessen"),
  // Then neither call throws and the stick-events table holds exactly
  //   one row at stickIndex 0 — the second tap must either queue behind
  //   the first (landing at stickIndex 1) or be ignored, never duplicate
  //   the index.
  //
  // Currently RED: both calls capture `currentIndex == 0` before the
  // first await, both call `_repo.recordStick(..., stickIndex: 0)`, and
  // the second insert blows up against the
  // `UNIQUE(session_id, stick_index)` index on `finisseur_stick_events`.
  // The thrown `SqliteException` escapes `Future.wait` and corrupts the
  // notifier's in-memory state.
  // ---------------------------------------------------------------------
  test(
    'parallel finisseur advance() never duplicates a stick row',
    () async {
      final notifier = container.read(activeFinisseurProvider.notifier);
      await notifier.startSession(playerId: playerId, field: 7, base: 3);
      final sessionId =
          container.read(activeFinisseurProvider).requireValue!.sessionId;

      notifier.updateCurrentStick(const StickResult(fieldHits: 1));

      // Two parallel advance taps — same snapshot, same stickIndex.
      // Capture any error from Future.wait so the test gets to the
      // assertion phase (Future.wait short-circuits on the first error).
      Object? raceError;
      try {
        await Future.wait<FinisseurAdvanceOutcome>([
          notifier.advance(),
          notifier.advance(),
        ]);
      } on Object catch (e) {
        raceError = e;
      }

      final stickEvents =
          await db.finisseurStickEventDao.forSession(sessionId);
      final atIndexZero =
          stickEvents.where((e) => e.stickIndex == 0).toList();

      expect(
        raceError,
        isNull,
        reason:
            'a parallel advance double-tap must not crash the notifier — '
            'today it trips the UNIQUE(session_id, stick_index) constraint',
      );
      expect(
        atIndexZero,
        hasLength(1),
        reason:
            'a single logical stock must produce a single stick row even '
            'under a parallel advance double-tap',
      );
    },
  );

  // ---------------------------------------------------------------------
  // R5-F-02 follow-up: after a parallel advance double-tap, the
  // notifier's `currentIndex` must match the number of persisted stick
  // rows so the next phase computation lines up.
  //
  // Given an active finisseur session and two parallel `advance()` calls,
  // When we ask both the in-memory state and the DB how far we are,
  // Then `state.currentIndex == stickEvents.length` (no drift between
  //   UI and storage), regardless of whether the second tap got
  //   serialised behind the first or coalesced away.
  //
  // Currently RED: the second `advance()` throws on the unique index, so
  // state already drifted before we get here — `currentIndex` jumped to
  // 1 from the first call's bump while the DB transactionally rolled
  // back the second insert (count stays at 1, but only by accident; the
  // assertion still holds only because both arms of the race wrote to
  // the same index). The deeper issue is that the notifier surfaces a
  // SqliteException to the UI instead of treating the second tap as a
  // queued/no-op interaction.
  // ---------------------------------------------------------------------
  test(
    'parallel finisseur advance() keeps state.currentIndex aligned with DB',
    () async {
      final notifier = container.read(activeFinisseurProvider.notifier);
      await notifier.startSession(playerId: playerId, field: 7, base: 3);
      final sessionId =
          container.read(activeFinisseurProvider).requireValue!.sessionId;

      notifier.updateCurrentStick(const StickResult(fieldHits: 1));

      Object? raceError;
      try {
        await Future.wait<FinisseurAdvanceOutcome>([
          notifier.advance(),
          notifier.advance(),
        ]);
      } on Object catch (e) {
        raceError = e;
      }

      expect(
        raceError,
        isNull,
        reason:
            'a clean mutex/queue around advance() should swallow the '
            'double-tap, not throw',
      );

      final state =
          container.read(activeFinisseurProvider).requireValue!;
      final stickEvents =
          await db.finisseurStickEventDao.forSession(sessionId);

      expect(
        state.currentIndex,
        stickEvents.length,
        reason:
            'UI index and persisted stick count must not diverge under a '
            'parallel advance double-tap',
      );
    },
  );

}
