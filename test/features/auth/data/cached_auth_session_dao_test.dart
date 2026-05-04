import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';

import '../../../_helpers/sqlite_open.dart';

void main() {
  setUpAll(registerLinuxSqliteOverride);

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('current() returns null on a fresh database', () async {
    expect(await db.cachedAuthSessionDao.current(), isNull);
  });

  test('upsert() inserts a row that current() then returns', () async {
    final dao = db.cachedAuthSessionDao;
    final now = DateTime.utc(2026, 5, 4, 12);

    await dao.upsert(
      userId: 'user-1',
      kind: 'keypair',
      displayName: 'Lukas',
      avatarColor: '#FF8800',
      expiresAt: now.add(const Duration(hours: 1)),
      refreshAfter: now.add(const Duration(minutes: 50)),
    );

    final row = await dao.current();
    expect(row, isNotNull);
    expect(row!.id, 'singleton');
    expect(row.userId, 'user-1');
    expect(row.kind, 'keypair');
    expect(row.displayName, 'Lukas');
    expect(row.avatarColor, '#FF8800');
  });

  test('a second upsert() updates instead of inserting a new row', () async {
    final dao = db.cachedAuthSessionDao;
    final t0 = DateTime.utc(2026, 5, 4, 12);

    await dao.upsert(
      userId: 'user-1',
      kind: 'keypair',
      displayName: 'Lukas',
      expiresAt: t0.add(const Duration(hours: 1)),
      refreshAfter: t0.add(const Duration(minutes: 50)),
    );

    await dao.upsert(
      userId: 'user-1',
      kind: 'oauth_google',
      displayName: 'Lukas Brosi',
      avatarColor: '#3366FF',
      expiresAt: t0.add(const Duration(hours: 2)),
      refreshAfter: t0.add(const Duration(minutes: 110)),
    );

    final all = await db.select(db.cachedAuthSession).get();
    expect(all.length, 1);
    expect(all.first.kind, 'oauth_google');
    expect(all.first.displayName, 'Lukas Brosi');
    expect(all.first.avatarColor, '#3366FF');
  });

  test('upsert() preserves createdAt across updates', () async {
    final dao = db.cachedAuthSessionDao;
    final t0 = DateTime.utc(2026, 5, 4, 12);

    await dao.upsert(
      userId: 'user-1',
      kind: 'keypair',
      displayName: 'Lukas',
      expiresAt: t0.add(const Duration(hours: 1)),
      refreshAfter: t0.add(const Duration(minutes: 50)),
    );
    final firstCreatedAt = (await dao.current())!.createdAt;

    await dao.upsert(
      userId: 'user-1',
      kind: 'oauth_apple',
      displayName: 'Lukas',
      expiresAt: t0.add(const Duration(hours: 2)),
      refreshAfter: t0.add(const Duration(minutes: 110)),
    );
    final updated = await dao.current();
    expect(updated!.createdAt, firstCreatedAt);
    // updatedAt is refreshed but drift stores DateTime at second resolution;
    // strict `isAfter` is unreliable in fast tests. Sufficient to assert it
    // is at least the original createdAt.
    expect(
      updated.updatedAt.isBefore(firstCreatedAt),
      isFalse,
      reason: 'updatedAt must not regress backwards',
    );
  });

  test('clear() removes the row and current() returns null again', () async {
    final dao = db.cachedAuthSessionDao;
    final now = DateTime.utc(2026, 5, 4, 12);

    await dao.upsert(
      userId: 'user-1',
      kind: 'keypair',
      displayName: 'Lukas',
      expiresAt: now.add(const Duration(hours: 1)),
      refreshAfter: now.add(const Duration(minutes: 50)),
    );
    expect(await dao.current(), isNotNull);

    await dao.clear();
    expect(await dao.current(), isNull);
  });

  test('watch() emits the current row on subscription and after upsert',
      () async {
    final dao = db.cachedAuthSessionDao;
    final now = DateTime.utc(2026, 5, 4, 12);

    final emissions = <CachedAuthSessionData?>[];
    final sub = dao.watch().listen(emissions.add);

    // Wait for the initial emission.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(emissions, [null]);

    await dao.upsert(
      userId: 'user-1',
      kind: 'keypair',
      displayName: 'Lukas',
      expiresAt: now.add(const Duration(hours: 1)),
      refreshAfter: now.add(const Duration(minutes: 50)),
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(emissions.length, 2);
    expect(emissions.last!.userId, 'user-1');

    await sub.cancel();
  });
}
