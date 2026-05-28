import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_score_draft_controller.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../../_helpers/sqlite_open.dart';

void main() {
  setUpAll(registerLinuxSqliteOverride);

  ProviderContainer makeContainer(AppDatabase db) {
    final c = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(c.dispose);
    return c;
  }

  const matchId = TournamentMatchId('m-test');
  final provider = scoreDraftControllerProvider(matchId);

  test('init hydrates from DAO and survives container rebuild', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    final c1 = makeContainer(db);
    await c1.read(provider.notifier).setSets(0, [
      const ScoreDraftSet(basekubbsA: 5, basekubbsB: 3, king: SetWinner.teamA),
      const ScoreDraftSet(basekubbsA: 2, basekubbsB: 5, king: SetWinner.teamB),
    ]);
    // Simulate app restart by creating a fresh container against the
    // same on-disk-equivalent (in-memory) database.
    final c2 = makeContainer(db);
    await c2.read(provider.notifier).init(0);
    final state = c2.read(provider);
    expect(state.hydratedForRound, 0);
    expect(state.sets, hasLength(2));
    expect(state.sets[0].basekubbsA, 5);
    expect(state.sets[0].king, SetWinner.teamA);
    expect(state.sets[1].basekubbsB, 5);
    expect(state.sets[1].king, SetWinner.teamB);
  });

  test('init with no persisted row falls back to a single empty set',
      () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    final c = makeContainer(db);
    await c.read(provider.notifier).init(0);
    final state = c.read(provider);
    expect(state.hydratedForRound, 0);
    expect(state.sets, hasLength(1));
    expect(state.sets.single.basekubbsA, 0);
    expect(state.sets.single.king, isNull);
  });

  test('clear with consensusRound wipes only that row (DSCORE-21)', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    final c = makeContainer(db);
    final notifier = c.read(provider.notifier);
    await notifier.setSets(1, [
      const ScoreDraftSet(basekubbsA: 4, basekubbsB: 5, king: SetWinner.teamB),
    ]);
    await notifier.setSets(2, [
      const ScoreDraftSet(basekubbsA: 5, king: SetWinner.teamA),
    ]);
    await notifier.clear(consensusRound: 1);
    // State resets to the cleared round.
    expect(c.read(provider).sets.single.basekubbsA, 0);
    // Round 2 row still hydrates on a fresh container.
    final c2 = makeContainer(db);
    await c2.read(provider.notifier).init(2);
    expect(c2.read(provider).sets.single.king, SetWinner.teamA);
    await c2.read(provider.notifier).init(1);
    expect(c2.read(provider).sets.single.basekubbsA, 0);
  });
}
