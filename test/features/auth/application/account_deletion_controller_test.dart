import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/features/auth/application/account_deletion_controller.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/data/auth_telemetry.dart';
import 'package:kubb_app/features/auth/data/crypto_service.dart';
import 'package:kubb_app/features/auth/data/keypair_storage.dart';
import 'package:kubb_app/features/auth/data/secure_token_store.dart';
import 'package:logging/logging.dart';

import '../../../_helpers/sqlite_open.dart';
import '../../../fixtures/auth/fake_secure_token_store.dart';
import '../../../fixtures/auth/fake_supabase_auth_adapter.dart';

void main() {
  setUpAll(registerLinuxSqliteOverride);

  late AppDatabase db;
  late FakeSupabaseAuthAdapter adapter;
  late FakeSecureTokenStore secureStore;
  late KeypairStorage keypair;
  late Logger telemetryLogger;
  late List<LogRecord> telemetryRecords;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    adapter = FakeSupabaseAuthAdapter();
    secureStore = FakeSecureTokenStore();
    // Real KeypairStorage wired to the in-memory secure-store fake so
    // we can assert clear() actually removed the private key.
    // The crypto service is irrelevant to the deletion flow — clear()
    // routes straight to the secure-store fake — but `KeypairStorage`
    // demands a concrete instance, so the production constructor with
    // default algorithms is the cheapest valid choice.
    keypair = KeypairStorage(
      crypto: CryptoService(),
      secureStore: secureStore,
    );
    telemetryRecords = <LogRecord>[];
    telemetryLogger = Logger.detached('auth-test-${identityHashCode(db)}')
      ..level = Level.ALL;
    telemetryLogger.onRecord.listen(telemetryRecords.add);

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        supabaseAuthAdapterProvider.overrideWithValue(adapter),
        keypairStorageProvider.overrideWithValue(keypair),
        secureTokenStoreProvider.overrideWithValue(secureStore),
        authTelemetryProvider
            .overrideWithValue(AuthTelemetry(logger: telemetryLogger)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await adapter.dispose();
    await db.close();
  });

  /// Inserts the acceptance-criteria fixture into [db]:
  ///   • one player
  ///   • 12 sessions (with one session_event each so the child table is
  ///     also populated)
  ///   • 3 outbox rows
  ///   • 2 tournament-score drafts
  ///   • one app-settings row and one cached-auth-session row so every
  ///     drift-owned table holds at least one value before the wipe.
  Future<void> seedUserData() async {
    const userId = 'fake-user-keypair';
    final ts = DateTime.utc(2026, 5);
    await db.playerDao.insert(
      PlayersCompanion(
        id: const Value(userId),
        name: const Value('Lukas'),
        deviceId: const Value('device-1'),
        createdAt: Value(ts),
      ),
    );
    for (var i = 0; i < 12; i++) {
      final sessionId = 's-$i';
      await db.sessionDao.insert(
        SessionsCompanion(
          id: Value(sessionId),
          playerId: const Value(userId),
          kind: const Value('sniper'),
          distanceMeters: const Value(8),
          status: const Value('completed'),
          startedAt: Value(ts.add(Duration(hours: i))),
          completedAt: Value(ts.add(Duration(hours: i, minutes: 5))),
        ),
      );
      await db.sessionEventDao.insert(
        SessionEventsCompanion(
          id: Value('e-$i'),
          sessionId: Value(sessionId),
          kind: const Value('hit'),
          createdAt: Value(ts.add(Duration(hours: i, minutes: 1))),
        ),
      );
      await db.finisseurStickEventDao.insert(
        FinisseurStickEventsCompanion(
          id: Value('f-$i'),
          sessionId: Value(sessionId),
          stickIndex: const Value(0),
          createdAt: Value(ts.add(Duration(hours: i, minutes: 2))),
        ),
      );
    }
    for (var i = 0; i < 3; i++) {
      await db.scoreSubmissionOutboxDao.insert(
        ScoreSubmissionOutboxCompanion.insert(
          matchId: 'm-$i',
          consensusRound: 0,
          setIndex: i,
          submitterUserId: userId,
          lamportCounter: i,
          lamportDeviceId: 'device-1',
          scoreJson: '{}',
          queuedAt: ts,
        ),
      );
    }
    for (var i = 0; i < 2; i++) {
      await db.into(db.tournamentScoreDrafts).insert(
            TournamentScoreDraftsCompanion.insert(
              matchId: 'tournament-m-$i',
              consensusRound: 0,
              payload: '[]',
              updatedAt: ts,
            ),
          );
    }
    await db.appSettingsDao.save('heliTracking', 'true');
    await db.cachedAuthSessionDao.upsert(
      userId: userId,
      kind: 'keypair',
      displayName: 'Lukas',
      expiresAt: ts.add(const Duration(hours: 1)),
      refreshAfter: ts.add(const Duration(minutes: 50)),
    );
  }

  /// Reads every DAO-exposed aggregate that surfaces user data. Returns
  /// the per-table row counts so individual tables can be inspected by
  /// name in the property assertion.
  Future<Map<String, int>> daoAggregateCounts() async {
    final perTable = <String, int>{};
    for (final table in db.allTables) {
      final rows = await db.select(table).get();
      perTable[table.actualTableName] = rows.length;
    }
    return perTable;
  }

  test('seed → delete() empties every drift-owned table (GDPR Art. 17)',
      () async {
    await adapter.signInAnonymously();
    // The deletion flow snapshots `currentState.userId` before the
    // server delete clears it; the seed itself is keyed off a stable
    // 'fake-user-keypair' player id so the fixture is independent of
    // adapter implementation details.
    expect(adapter.currentState.userId, isNotNull);
    await seedUserData();
    final before = await daoAggregateCounts();
    expect(before['players'], greaterThan(0));
    expect(before['sessions'], 12);
    expect(before['session_events'], 12);
    expect(before['finisseur_stick_events'], 12);
    expect(before['score_submission_outbox'], 3);
    expect(before['tournament_score_drafts'], 2);
    expect(before['app_settings_table'], 1);
    expect(before['cached_auth_session'], 1);
    // A private key is on disk before deletion so we can prove clear()
    // ran as part of the flow.
    await secureStore.write(SecureTokenKind.privateKey, 'seed-key');

    await container
        .read(accountDeletionControllerProvider.notifier)
        .delete();

    expect(
      container.read(accountDeletionControllerProvider),
      const AccountDeletionState.done(),
    );

    // Property: every drift-owned table is empty after delete(). This
    // covers Players, Sessions, SessionEvents, AppSettingsTable,
    // FinisseurStickEvents, CachedAuthSession, TournamentScoreDrafts
    // and ScoreSubmissionOutbox without an explicit table-by-table list
    // so the assertion survives future `tables:` additions.
    final after = await daoAggregateCounts();
    for (final entry in after.entries) {
      expect(
        entry.value,
        0,
        reason: 'table "${entry.key}" still has ${entry.value} rows '
            'after AccountDeletionController.delete()',
      );
    }

    // Ordering: server delete first, then drift wipe, then keypair clear.
    expect(adapter.deleteAccountCount, 1);
    expect(
      await secureStore.read(SecureTokenKind.privateKey),
      isNull,
      reason: 'keypair.clear() must run after the drift wipe',
    );

    // Both telemetry events are emitted: the original accountDelete and
    // the new accountDeleteWipedLocal that records the GDPR Art. 17
    // device-local cleanup.
    final messages = telemetryRecords.map((r) => r.message).toList();
    expect(
      messages.any((m) => m.contains('accountDeleteWipedLocal')),
      isTrue,
      reason: 'expected accountDeleteWipedLocal in $messages',
    );
    expect(
      messages.any((m) => m.contains('accountDelete ')),
      isTrue,
      reason: 'expected accountDelete in $messages',
    );
  });

  test('server delete failure leaves drift untouched (no partial wipe)',
      () async {
    await adapter.signInAnonymously();
    await seedUserData();
    final before = await daoAggregateCounts();
    await secureStore.write(SecureTokenKind.privateKey, 'seed-key');

    adapter.throwOnNextCall = StateError('server-unreachable');

    await container
        .read(accountDeletionControllerProvider.notifier)
        .delete();

    final state = container.read(accountDeletionControllerProvider);
    expect(state, isA<AccountDeletionState>());
    expect(
      state.toString(),
      contains('server-unreachable'),
      reason: 'controller must surface the server-side failure',
    );

    // Drift untouched: every counted row is still there.
    final after = await daoAggregateCounts();
    expect(after, before);

    // Keypair untouched: clearing the seed key would lock the user out
    // of retrying the deletion against the still-live server account.
    expect(
      await secureStore.read(SecureTokenKind.privateKey),
      'seed-key',
    );

    // No drift-wipe telemetry was emitted because the wipe never ran.
    expect(
      telemetryRecords.any((r) => r.message.contains('accountDeleteWipedLocal')),
      isFalse,
    );
  });
}
