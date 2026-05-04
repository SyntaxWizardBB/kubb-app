import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/features/training/application/active_finisseur_notifier.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';

import '../../../_helpers/sqlite_open.dart';

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

void main() {
  const playerId = 'p1';
  late AppDatabase db;
  late ProviderContainer container;

  setUpAll(registerLinuxSqliteOverride);

  setUp(() async {
    db = await openTestDatabase();
    await _seedPlayer(db, playerId);
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
  });

  tearDown(() async {
    await db.close();
  });

  test('startSession produces a fresh state with six untouched sticks',
      () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 7, base: 3);

    final state = container.read(activeFinisseurProvider).requireValue!;
    expect(state.field, 7);
    expect(state.base, 3);
    expect(state.sticks, hasLength(6));
    expect(state.currentIndex, 0);
    expect(state.sticks.every((s) => s.isUntouched), isTrue);
  });

  test('updateCurrentStick mutates only the active stick', () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 7, base: 3);
    notifier.updateCurrentStick(const StickResult(fieldHits: 2));

    final state = container.read(activeFinisseurProvider).requireValue!;
    expect(state.sticks[0].fieldHits, 2);
    expect(state.sticks[1].isUntouched, isTrue);
  });

  test('advance persists current stick and increments the index', () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 7, base: 3);
    notifier.updateCurrentStick(
      const StickResult(fieldHits: 3, eightMHit: true),
    );
    final outcome = await notifier.advance();

    expect(outcome, FinisseurAdvanceOutcome.carryOn);
    final state = container.read(activeFinisseurProvider).requireValue!;
    expect(state.currentIndex, 1);

    final id = state.sessionId;
    final stickEvents = await db.finisseurStickEventDao.forSession(id);
    expect(stickEvents, hasLength(1));
    expect(stickEvents.single.fieldKubbsHit, 3);
    expect(stickEvents.single.eightMHit, isTrue);
  });

  test('advance on stick 5 with continue setting off ends the session',
      () async {
    await db.appSettingsDao.save('allowContinueBeyondSticks', 'false');
    await container.read(appSettingsProvider.future);
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 7, base: 3);
    var outcome = FinisseurAdvanceOutcome.carryOn;
    for (var i = 0; i < 6; i++) {
      outcome = await notifier.advance();
    }
    expect(outcome, FinisseurAdvanceOutcome.done);
  });

  test('complete clears state and marks session completed', () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 5, base: 5);
    final id = container.read(activeFinisseurProvider).requireValue!.sessionId;

    await notifier.complete();

    expect(container.read(activeFinisseurProvider).requireValue, isNull);
    final stored = await db.sessionDao.getById(id);
    expect(stored?.status, 'completed');
  });

  test('abortAndDelete removes session and stick events', () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 7, base: 3);
    notifier.updateCurrentStick(const StickResult(fieldHits: 1));
    await notifier.advance();

    final id = container.read(activeFinisseurProvider).requireValue!.sessionId;
    await notifier.abortAndDelete();

    expect(container.read(activeFinisseurProvider).requireValue, isNull);
    expect(await db.sessionDao.getById(id), isNull);
    expect(await db.finisseurStickEventDao.forSession(id), isEmpty);
  });

  test('remainingFieldBeforeCurrent reflects prior sticks only', () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 7, base: 3);
    notifier.updateCurrentStick(const StickResult(fieldHits: 3));
    await notifier.advance();
    notifier.updateCurrentStick(const StickResult(fieldHits: 2));
    await notifier.advance();

    final state = container.read(activeFinisseurProvider).requireValue!;
    expect(state.currentIndex, 2);
    expect(state.remainingFieldBeforeCurrent, 2);
    expect(state.remainingBaseBeforeCurrent, 3);
  });

  test('rollbackLastStick removes the last stick and rewinds the index',
      () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 7, base: 3);
    notifier.updateCurrentStick(const StickResult(fieldHits: 3));
    await notifier.advance();
    notifier.updateCurrentStick(const StickResult(fieldHits: 2));
    await notifier.advance();

    final ok = await notifier.rollbackLastStick();
    expect(ok, isTrue);

    final state = container.read(activeFinisseurProvider).requireValue!;
    expect(state.currentIndex, 1);
    final id = state.sessionId;
    final stickEvents = await db.finisseurStickEventDao.forSession(id);
    expect(stickEvents, hasLength(1));
    expect(stickEvents.single.stickIndex, 0);
  });

  test('advance reports finished early when all kubbs are down with king off',
      () async {
    await db.appSettingsDao.save('kingThrowTracking', 'false');
    await container.read(appSettingsProvider.future);

    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 1, base: 1);
    notifier.updateCurrentStick(
      const StickResult(fieldHits: 1, eightMHit: true),
    );
    final done = await notifier.advance();

    expect(done, FinisseurAdvanceOutcome.done);
  });

  test('advance reports finished only on king hit when king tracking is on',
      () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 1, base: 1);

    notifier.updateCurrentStick(
      const StickResult(fieldHits: 1, eightMHit: true),
    );
    expect(await notifier.advance(), FinisseurAdvanceOutcome.carryOn);

    notifier.updateCurrentStick(
      const StickResult(king: KingResult(hit: true)),
    );
    expect(await notifier.advance(), FinisseurAdvanceOutcome.done);
  });

  test('rollbackLastStick is a no-op when sitting at stick 0', () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 7, base: 3);
    final ok = await notifier.rollbackLastStick();
    expect(ok, isFalse);
  });

  test('starting a new session discards a prior active finisseur', () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 7, base: 3);
    final firstId =
        container.read(activeFinisseurProvider).requireValue!.sessionId;

    await notifier.startSession(playerId: playerId, field: 5, base: 5);

    expect(await db.sessionDao.getById(firstId), isNull);
  });

  test('stock 6 without victory raises continue decision when setting on',
      () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 7, base: 3);

    // Burn six sticks without winning. Field=7 needs more than six pure
    // misses to flip phase, which suits this test.
    var outcome = FinisseurAdvanceOutcome.carryOn;
    for (var i = 0; i < 6; i++) {
      outcome = await notifier.advance();
    }

    expect(outcome, FinisseurAdvanceOutcome.needsContinueDecision);
    final state = container.read(activeFinisseurProvider).requireValue!;
    expect(state.phase, FinisseurPhase.awaitingContinueDecision);
  });

  test('continueBeyondStocks extends the buffer and unlocks the next stick',
      () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 7, base: 3);
    for (var i = 0; i < 6; i++) {
      await notifier.advance();
    }
    expect(
      container.read(activeFinisseurProvider).requireValue!.phase,
      FinisseurPhase.awaitingContinueDecision,
    );

    await notifier.continueBeyondStocks();

    final state = container.read(activeFinisseurProvider).requireValue!;
    expect(state.continuedBeyondSticks, isTrue);
    expect(state.sticks, hasLength(7));
    expect(state.phase, isNot(FinisseurPhase.awaitingContinueDecision));
  });

  test('giveUp marks the session completed and clears the state', () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 7, base: 3);
    for (var i = 0; i < 6; i++) {
      await notifier.advance();
    }
    final id = container.read(activeFinisseurProvider).requireValue!.sessionId;

    await notifier.giveUp();

    expect(container.read(activeFinisseurProvider).requireValue, isNull);
    final stored = await db.sessionDao.getById(id);
    expect(stored?.status, 'completed');
  });

  test('king phase activates after all base kubbs fall with king on',
      () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 1, base: 1);

    // Stick 0: clear field + base. King-throw is its own next stick.
    notifier.updateCurrentStick(
      const StickResult(fieldHits: 1, eightMHit: true),
    );
    final outcome = await notifier.advance();

    expect(outcome, FinisseurAdvanceOutcome.carryOn);
    final state = container.read(activeFinisseurProvider).requireValue!;
    expect(state.phase, FinisseurPhase.king);
    // Pre-seeded king-result so a single Stock-abschliessen tap commits it.
    expect(state.current.king?.hit, isTrue);
  });

  test('hits in Verlängerung decrement remaining base kubbs', () async {
    await db.appSettingsDao.save('kingThrowTracking', 'false');
    await container.read(appSettingsProvider.future);

    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 0, base: 3);
    for (var i = 0; i < 6; i++) {
      await notifier.advance();
    }
    await notifier.continueBeyondStocks();

    notifier.updateCurrentStick(const StickResult(eightMHit: true));
    expect(await notifier.advance(), FinisseurAdvanceOutcome.carryOn);
    var state = container.read(activeFinisseurProvider).requireValue!;
    expect(state.remainingBaseBeforeCurrent, 2);
    expect(state.sticks, hasLength(8));

    notifier.updateCurrentStick(const StickResult(eightMHit: true));
    expect(await notifier.advance(), FinisseurAdvanceOutcome.carryOn);
    state = container.read(activeFinisseurProvider).requireValue!;
    expect(state.remainingBaseBeforeCurrent, 1);

    notifier.updateCurrentStick(const StickResult(eightMHit: true));
    expect(await notifier.advance(), FinisseurAdvanceOutcome.done);
  });

  test('rollbackLastStick survives Verlängerung and rewinds across the boundary',
      () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 7, base: 3);
    for (var i = 0; i < 6; i++) {
      await notifier.advance();
    }
    await notifier.continueBeyondStocks();
    notifier.updateCurrentStick(const StickResult(eightMHit: true));
    await notifier.advance();
    notifier.updateCurrentStick(const StickResult(eightMHit: true));
    await notifier.advance();

    var state = container.read(activeFinisseurProvider).requireValue!;
    expect(state.currentIndex, 8);

    expect(await notifier.rollbackLastStick(), isTrue);
    state = container.read(activeFinisseurProvider).requireValue!;
    expect(state.currentIndex, 7);
    expect(state.sticks, hasLength(8));

    expect(await notifier.rollbackLastStick(), isTrue);
    state = container.read(activeFinisseurProvider).requireValue!;
    expect(state.currentIndex, 6);
    expect(state.sticks, hasLength(7));
  });

  test('rollback from first Verlängerungs-stick clears the continue flag',
      () async {
    final notifier = container.read(activeFinisseurProvider.notifier);
    await notifier.startSession(playerId: playerId, field: 7, base: 3);
    for (var i = 0; i < 6; i++) {
      await notifier.advance();
    }
    await notifier.continueBeyondStocks();
    final beforeRollback =
        container.read(activeFinisseurProvider).requireValue!;
    expect(beforeRollback.currentIndex, 6);
    expect(beforeRollback.continuedBeyondSticks, isTrue);

    expect(await notifier.rollbackLastStick(), isTrue);
    final state = container.read(activeFinisseurProvider).requireValue!;
    expect(state.currentIndex, 5);
    expect(state.sticks, hasLength(6));
    expect(state.continuedBeyondSticks, isFalse);
  });
}
