import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/achievements/data/achievements_repository.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/data/match_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Fake match repository so the post-finalize badge hook can be driven
/// without standing up a Supabase client. `noSuchMethod` returns Future
/// nulls for every untouched method, so we only override the call sites
/// the hook actually uses: `proposeResult` (to drive finalize status)
/// and `listForCaller` (to feed lifetime aggregates back into the
/// listener).
class _FakeMatchRepo implements MatchRepository {
  _FakeMatchRepo({required this.proposeStatus, required this.summaries});

  final MatchStatus proposeStatus;
  final List<MatchSummary> summaries;

  @override
  Future<MatchProposeResultResponse> proposeResult(
    String matchId, {
    required String? winnerTeamId,
    required int scoreA,
    required int scoreB,
  }) async {
    return MatchProposeResultResponse(status: proposeStatus, round: 1);
  }

  @override
  Future<List<MatchSummary>> listForCaller({MatchStatus? statusFilter}) async {
    return summaries;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

MatchSummary _finalized({
  required String matchId,
  required String myTeamId,
  required String winnerTeamId,
}) {
  return MatchSummary(
    matchId: matchId,
    format: MatchFormat.bo1,
    scoring: MatchScoring.wins,
    status: MatchStatus.finalized,
    startedAt: DateTime.utc(2026, 5, 28, 10),
    completedAt: DateTime.utc(2026, 5, 28, 11),
    myTeamId: myTeamId,
    opponentTeamSize: 1,
    myRole: MatchRole.participant,
    winnerTeamId: winnerTeamId,
  );
}

void main() {
  const playerId = 'user-1';

  test('proposeResult that finalizes the match unlocks first_match',
      () async {
    final repo = InMemoryAchievementsRepository();
    addTearDown(repo.dispose);

    final fake = _FakeMatchRepo(
      proposeStatus: MatchStatus.finalized,
      summaries: [
        _finalized(
          matchId: 'match-A',
          myTeamId: 'A',
          winnerTeamId: 'A',
        ),
      ],
    );

    final container = ProviderContainer(
      overrides: [
        matchRepositoryProvider.overrideWithValue(fake),
        achievementsRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWith((_) => playerId),
      ],
    );
    addTearDown(container.dispose);

    await container.read(matchActionsProvider).proposeResult(
          'match-A',
          winnerTeamId: 'A',
          scoreA: 1,
          scoreB: 0,
        );

    final unlocks = await repo.listUnlocksFor(const UserId(playerId));
    final ids = unlocks.map((u) => u.badgeId).toSet();
    expect(ids, contains('first_match'));
    expect(
      unlocks.firstWhere((u) => u.badgeId == 'first_match').sourceSessionId,
      'match-A',
    );
  });

  test('non-finalized propose result does NOT trigger the badge hook',
      () async {
    final repo = InMemoryAchievementsRepository();
    addTearDown(repo.dispose);

    final fake = _FakeMatchRepo(
      proposeStatus: MatchStatus.awaitingResults,
      summaries: const <MatchSummary>[],
    );

    final container = ProviderContainer(
      overrides: [
        matchRepositoryProvider.overrideWithValue(fake),
        achievementsRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWith((_) => playerId),
      ],
    );
    addTearDown(container.dispose);

    await container.read(matchActionsProvider).proposeResult(
          'match-A',
          winnerTeamId: 'A',
          scoreA: 1,
          scoreB: 0,
        );

    final unlocks = await repo.listUnlocksFor(const UserId(playerId));
    expect(unlocks, isEmpty);
  });

  test('50 finalized matches unlock matches_50 alongside first_match',
      () async {
    final repo = InMemoryAchievementsRepository();
    addTearDown(repo.dispose);

    final fifty = List.generate(
      50,
      (i) => _finalized(
        matchId: 'match-$i',
        myTeamId: 'A',
        winnerTeamId: 'A',
      ),
    );

    final fake = _FakeMatchRepo(
      proposeStatus: MatchStatus.finalized,
      summaries: fifty,
    );

    final container = ProviderContainer(
      overrides: [
        matchRepositoryProvider.overrideWithValue(fake),
        achievementsRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWith((_) => playerId),
      ],
    );
    addTearDown(container.dispose);

    await container.read(matchActionsProvider).proposeResult(
          'match-49',
          winnerTeamId: 'A',
          scoreA: 1,
          scoreB: 0,
        );

    final ids = (await repo.listUnlocksFor(const UserId(playerId)))
        .map((u) => u.badgeId)
        .toSet();
    expect(ids, containsAll(<String>['first_match', 'matches_50']));
  });
}
