import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';

import '../../../_helpers/sqlite_open.dart';

/// Direct DAO tests for the v7 inbox cache. They lean on
/// [NativeDatabase.memory] so the migration path and the table shape
/// are both exercised — no test would catch a schema-version
/// regression more clearly than failing to read back a row that was
/// just written.
void main() {
  setUpAll(registerLinuxSqliteOverride);

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  InboxMessagesCompanion mkRow({
    required String id,
    required String userId,
    String kind = 'notice',
    int createdAt = 1_700_000_000_000,
    int? readAt,
    int? repliedAt,
    String bodyJson = '{}',
  }) {
    return InboxMessagesCompanion(
      id: Value(id),
      userId: Value(userId),
      kind: Value(kind),
      bodyJson: Value(bodyJson),
      createdAt: Value(createdAt),
      readAt: Value(readAt),
      repliedAt: Value(repliedAt),
    );
  }

  test('listByUser() returns rows newest first', () async {
    final dao = db.inboxMessagesDao;
    await dao.upsertMany([
      mkRow(id: 'a', userId: 'u1', createdAt: 100),
      mkRow(id: 'b', userId: 'u1', createdAt: 300),
      mkRow(id: 'c', userId: 'u1', createdAt: 200),
    ]);

    final rows = await dao.listByUser('u1');
    expect(rows.map((r) => r.id).toList(), ['b', 'c', 'a']);
  });

  test('listByUser() ignores rows owned by other users', () async {
    final dao = db.inboxMessagesDao;
    await dao.upsertMany([
      mkRow(id: 'a', userId: 'u1'),
      mkRow(id: 'b', userId: 'u2'),
    ]);

    final rows = await dao.listByUser('u1');
    expect(rows.map((r) => r.id).toList(), ['a']);
  });

  test('upsertMany() updates rows on primary-key collision', () async {
    final dao = db.inboxMessagesDao;
    await dao.upsertMany([
      mkRow(id: 'a', userId: 'u1', bodyJson: '{"v":1}'),
    ]);
    await dao.upsertMany([
      mkRow(id: 'a', userId: 'u1', bodyJson: '{"v":2}', readAt: 42),
    ]);

    final rows = await dao.listByUser('u1');
    expect(rows, hasLength(1));
    expect(rows.single.bodyJson, '{"v":2}');
    expect(rows.single.readAt, 42);
  });

  test("deleteForUser() drops only the named user's rows", () async {
    final dao = db.inboxMessagesDao;
    await dao.upsertMany([
      mkRow(id: 'a', userId: 'u1'),
      mkRow(id: 'b', userId: 'u1'),
      mkRow(id: 'c', userId: 'u2'),
    ]);

    final removed = await dao.deleteForUser('u1');
    expect(removed, 2);
    expect(await dao.listByUser('u1'), isEmpty);
    expect((await dao.listByUser('u2')).map((r) => r.id), ['c']);
  });

  test('deleteById() removes a single row regardless of owner', () async {
    final dao = db.inboxMessagesDao;
    await dao.upsertMany([
      mkRow(id: 'a', userId: 'u1'),
      mkRow(id: 'b', userId: 'u1'),
    ]);

    await dao.deleteById('a');
    expect((await dao.listByUser('u1')).map((r) => r.id), ['b']);
  });

  test('stampTimestamps() updates only the requested timestamp columns',
      () async {
    final dao = db.inboxMessagesDao;
    await dao.upsertMany([
      mkRow(id: 'a', userId: 'u1'),
    ]);

    await dao.stampTimestamps('a', readAt: DateTime.utc(2026, 5, 28, 12));
    final afterRead = (await dao.listByUser('u1')).single;
    expect(afterRead.readAt, isNotNull);
    expect(afterRead.repliedAt, isNull);

    await dao.stampTimestamps('a', repliedAt: DateTime.utc(2026, 5, 28, 13));
    final afterReply = (await dao.listByUser('u1')).single;
    expect(afterReply.readAt, isNotNull);
    expect(afterReply.repliedAt, isNotNull);
  });

  test('watchByUser() emits initial snapshot and after every upsert',
      () async {
    final dao = db.inboxMessagesDao;
    final emissions = <List<String>>[];

    final sub = dao
        .watchByUser('u1')
        .listen((rows) => emissions.add(rows.map((r) => r.id).toList()));

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(emissions, [<String>[]]);

    await dao.upsertMany([
      mkRow(id: 'a', userId: 'u1', createdAt: 100),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(emissions.last, ['a']);

    await dao.upsertMany([
      mkRow(id: 'b', userId: 'u1', createdAt: 200),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(emissions.last, ['b', 'a']);

    await sub.cancel();
  });
}
