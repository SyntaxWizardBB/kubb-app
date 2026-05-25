import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../../_helpers/sqlite_open.dart';

void main() {
  late AppDatabase db;

  setUpAll(registerLinuxSqliteOverride);

  setUp(() async {
    db = await openTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  const matchA = TournamentMatchId('match-a');
  const matchB = TournamentMatchId('match-b');

  SetScore set(int a, int b, SetWinner w) =>
      SetScore(basekubbsKnockedByA: a, basekubbsKnockedByB: b, winner: w);

  test('load returns null when no draft has been persisted', () async {
    final result = await db.tournamentScoreDraftDao.load(matchA, 0);
    expect(result, isNull);
  });

  test('save then load returns the same sets in order', () async {
    final sets = [
      set(6, 4, SetWinner.teamA),
      set(2, 6, SetWinner.teamB),
    ];

    await db.tournamentScoreDraftDao.save(matchA, 0, sets);
    final loaded = await db.tournamentScoreDraftDao.load(matchA, 0);

    expect(loaded, isNotNull);
    expect(loaded!.length, 2);
    expect(loaded[0], sets[0]);
    expect(loaded[1], sets[1]);
  });

  test('save with same key overwrites previous payload', () async {
    await db.tournamentScoreDraftDao.save(
      matchA,
      0,
      [set(3, 0, SetWinner.teamA)],
    );
    await db.tournamentScoreDraftDao.save(
      matchA,
      0,
      [set(0, 5, SetWinner.teamB), set(1, 6, SetWinner.teamB)],
    );

    final loaded = await db.tournamentScoreDraftDao.load(matchA, 0);

    expect(loaded!.length, 2);
    expect(loaded[0].winner, SetWinner.teamB);
    expect(loaded[1].basekubbsKnockedByB, 6);
  });

  test(
    'clear with explicit consensusRound removes only that round',
    () async {
      await db.tournamentScoreDraftDao.save(
        matchA,
        0,
        [set(6, 4, SetWinner.teamA)],
      );
      await db.tournamentScoreDraftDao.save(
        matchA,
        1,
        [set(2, 6, SetWinner.teamB)],
      );

      await db.tournamentScoreDraftDao.clear(matchA, consensusRound: 0);

      expect(await db.tournamentScoreDraftDao.load(matchA, 0), isNull);
      final remaining = await db.tournamentScoreDraftDao.load(matchA, 1);
      expect(remaining, isNotNull);
      expect(remaining!.single.winner, SetWinner.teamB);
    },
  );

  test('clear without consensusRound removes every round of that match',
      () async {
    await db.tournamentScoreDraftDao
        .save(matchA, 0, [set(6, 4, SetWinner.teamA)]);
    await db.tournamentScoreDraftDao
        .save(matchA, 1, [set(2, 6, SetWinner.teamB)]);
    await db.tournamentScoreDraftDao
        .save(matchB, 0, [set(1, 0, SetWinner.teamA)]);

    await db.tournamentScoreDraftDao.clear(matchA);

    expect(await db.tournamentScoreDraftDao.load(matchA, 0), isNull);
    expect(await db.tournamentScoreDraftDao.load(matchA, 1), isNull);
    expect(
      await db.tournamentScoreDraftDao.load(matchB, 0),
      isNotNull,
    );
  });

  test('drafts for different matches are isolated by primary key', () async {
    await db.tournamentScoreDraftDao
        .save(matchA, 0, [set(6, 4, SetWinner.teamA)]);
    await db.tournamentScoreDraftDao
        .save(matchB, 0, [set(3, 6, SetWinner.teamB)]);

    final a = await db.tournamentScoreDraftDao.load(matchA, 0);
    final b = await db.tournamentScoreDraftDao.load(matchB, 0);

    expect(a!.single.winner, SetWinner.teamA);
    expect(b!.single.winner, SetWinner.teamB);
  });

  test('round-trip preserves both teamA and teamB winners', () async {
    final sets = [
      set(6, 0, SetWinner.teamA),
      set(0, 6, SetWinner.teamB),
      set(5, 6, SetWinner.teamB),
    ];

    await db.tournamentScoreDraftDao.save(matchA, 2, sets);
    final loaded = await db.tournamentScoreDraftDao.load(matchA, 2);

    expect(loaded!.map((s) => s.winner), [
      SetWinner.teamA,
      SetWinner.teamB,
      SetWinner.teamB,
    ]);
    expect(loaded.map((s) => s.basekubbsKnockedByA), [6, 0, 5]);
    expect(loaded.map((s) => s.basekubbsKnockedByB), [0, 6, 6]);
  });
}
