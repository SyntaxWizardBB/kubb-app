import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/player/data/player_repository.dart';

import '../../../_helpers/sqlite_open.dart';

void main() {
  late AppDatabase db;
  late PlayerRepository repo;

  setUpAll(registerLinuxSqliteOverride);

  setUp(() async {
    db = await openTestDatabase();
    repo = PlayerRepository(db.playerDao);
  });

  tearDown(() async {
    await db.close();
  });

  test('currentOrNull returns null when no profile exists', () async {
    final result = await repo.currentOrNull();

    expect(result, isNull);
  });

  test('create persists a player and currentOrNull returns it', () async {
    final created = await repo.create(name: 'Lukas');

    expect(created.name, 'Lukas');
    expect(created.deviceId, isNotEmpty);
    expect(created.id, isNot(created.deviceId));
    expect(
      created.createdAt.difference(DateTime.now().toUtc()).inSeconds.abs(),
      lessThan(5),
    );

    final loaded = await repo.currentOrNull();
    expect(loaded, isNotNull);
    expect(loaded!.id, created.id);
    expect(loaded.name, 'Lukas');
  });

  test('currentOrNull returns the oldest profile by createdAt asc', () async {
    final first = await repo.create(name: 'Anna');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.create(name: 'Bea');

    final loaded = await repo.currentOrNull();

    expect(loaded?.id, first.id);
    expect(loaded?.name, 'Anna');
  });

  test('watchCurrent emits null then the created player', () async {
    final stream = repo.watchCurrent();

    final future = expectLater(
      stream,
      emitsInOrder(<Matcher>[
        isNull,
        predicate<Player?>((p) => p != null && p.name == 'Lukas'),
      ]),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));
    await repo.create(name: 'Lukas');

    await future;
  });
}
