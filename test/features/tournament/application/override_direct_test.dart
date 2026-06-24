// Test fixtures intentionally interleave notifier mutations with awaits;
// suppressing this lint keeps the call-site readable as a story.
// ignore_for_file: cascade_invocations
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/tournament_override_controller.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

class _CapturingRemote implements TournamentRemote {
  ({TournamentMatchId id, List<SetScore> scores, String reason})? lastCall;

  @override
  Future<void> organizerOverride({
    required TournamentMatchId matchId,
    required List<SetScore> finalSetScores,
    required String reason,
  }) async {
    lastCall = (id: matchId, scores: finalSetScores, reason: reason);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ProviderContainer _container({TournamentRemote? remote}) {
  return ProviderContainer(
    overrides: [
      if (remote != null) tournamentRemoteProvider.overrideWithValue(remote),
    ],
  );
}

void main() {
  group('TournamentOverrideController.submitDirect', () {
    test('forwards a decisive score with no mandatory reason', () async {
      final remote = _CapturingRemote();
      final c = _container(remote: remote);
      addTearDown(c.dispose);
      final notifier = c.read(tournamentOverrideControllerProvider.notifier);
      notifier
        ..updateSet(
          0,
          const TournamentOverrideSetDraft(
              basekubbsA: 5, king: SetWinner.teamA),
        )
        ..addSet(maxSets: 3)
        ..updateSet(
          1,
          const TournamentOverrideSetDraft(
              basekubbsA: 5, king: SetWinner.teamA),
        );
      // No setReason call — the direct path must not require one.
      await notifier.submitDirect(const TournamentMatchId('m-1'), setsToWin: 2);

      expect(remote.lastCall, isNotNull);
      expect(remote.lastCall!.id, const TournamentMatchId('m-1'));
      expect(remote.lastCall!.reason, isEmpty);
      expect(remote.lastCall!.scores, hasLength(2));
      expect(remote.lastCall!.scores.first.winner, SetWinner.teamA);
    });

    test('forwards a reason when one happens to be set (optional, not forced)',
        () async {
      final remote = _CapturingRemote();
      final c = _container(remote: remote);
      addTearDown(c.dispose);
      final notifier = c.read(tournamentOverrideControllerProvider.notifier);
      notifier
        ..updateSet(
          0,
          const TournamentOverrideSetDraft(
              basekubbsB: 5, king: SetWinner.teamB),
        )
        ..addSet(maxSets: 3)
        ..updateSet(
          1,
          const TournamentOverrideSetDraft(
              basekubbsB: 5, king: SetWinner.teamB),
        )
        ..setReason('  Nachtrag  ');
      await notifier.submitDirect(const TournamentMatchId('m-2'), setsToWin: 2);

      expect(remote.lastCall!.reason, 'Nachtrag');
      expect(remote.lastCall!.scores.first.winner, SetWinner.teamB);
    });

    test('refuses only when the score is not decisive', () async {
      final remote = _CapturingRemote();
      final c = _container(remote: remote);
      addTearDown(c.dispose);
      final notifier = c.read(tournamentOverrideControllerProvider.notifier);
      // Blank reason but an undecided single set → still rejected, on the
      // score precondition, never on a reason precondition.
      await expectLater(
        notifier.submitDirect(const TournamentMatchId('m-1'), setsToWin: 2),
        throwsA(isA<StateError>()),
      );
      expect(remote.lastCall, isNull);
    });
  });
}
