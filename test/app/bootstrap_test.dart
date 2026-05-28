import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/app/bootstrap.dart';
import 'package:kubb_app/core/application/outbox_flusher_provider.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';

import '../_helpers/sqlite_open.dart';
import '../fixtures/auth/fake_supabase_auth_adapter.dart';

void main() {
  setUpAll(registerLinuxSqliteOverride);

  late AppDatabase db;
  late FakeSupabaseAuthAdapter adapter;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    adapter = FakeSupabaseAuthAdapter();
  });

  tearDown(() async {
    await adapter.dispose();
    await db.close();
  });

  // Outbox-GC (TASK-M4.3-T13) runs as a fire-and-forget step in
  // `appBootstrapProvider`. The in-memory DB satisfies the DAO read path
  // so the unawaited future completes cleanly in tests instead of
  // escaping the test zone via path_provider.

  test('appBootstrapProvider returns null on a fresh DAO', () async {
    final container = ProviderContainer(
      overrides: [
        cachedAuthSessionDaoProvider.overrideWithValue(db.cachedAuthSessionDao),
        scoreSubmissionOutboxDaoProvider
            .overrideWithValue(db.scoreSubmissionOutboxDao),
        // The W2-T1 keypair refresher is constructed eagerly in
        // bootstrap; without this override it would try to read
        // Supabase.instance, which is not initialised in this suite.
        supabaseAuthAdapterProvider.overrideWithValue(adapter),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(appBootstrapProvider.future);
    expect(result, isNull);
  });

  test('appBootstrapProvider returns the cached row when one exists',
      () async {
    final now = DateTime.utc(2026, 5, 4, 12);
    await db.cachedAuthSessionDao.upsert(
      userId: 'user-42',
      kind: 'oauth_google',
      displayName: 'Lukas',
      avatarColor: '#3366FF',
      expiresAt: now.add(const Duration(hours: 1)),
      refreshAfter: now.add(const Duration(minutes: 50)),
    );

    final container = ProviderContainer(
      overrides: [
        cachedAuthSessionDaoProvider.overrideWithValue(db.cachedAuthSessionDao),
        scoreSubmissionOutboxDaoProvider
            .overrideWithValue(db.scoreSubmissionOutboxDao),
        // The W2-T1 keypair refresher is constructed eagerly in
        // bootstrap; without this override it would try to read
        // Supabase.instance, which is not initialised in this suite.
        supabaseAuthAdapterProvider.overrideWithValue(adapter),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(appBootstrapProvider.future);
    expect(result, isNotNull);
    expect(result!.userId, 'user-42');
    expect(result.kind, 'oauth_google');
    expect(result.displayName, 'Lukas');
    expect(result.avatarColor, '#3366FF');
  });
}
