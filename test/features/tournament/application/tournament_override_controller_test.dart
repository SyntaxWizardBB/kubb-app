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
  group('TournamentOverrideController', () {
    test('addSet appends one set, capped at maxSets', () {
      final c = _container();
      addTearDown(c.dispose);
      final notifier = c.read(tournamentOverrideControllerProvider.notifier);
      expect(c.read(tournamentOverrideControllerProvider).sets, hasLength(1));
      notifier
        ..addSet(maxSets: 3)
        ..addSet(maxSets: 3)
        ..addSet(maxSets: 3); // hits cap
      expect(c.read(tournamentOverrideControllerProvider).sets, hasLength(3));
    });

    test('removeSet leaves at least one row', () {
      final c = _container();
      addTearDown(c.dispose);
      final notifier = c.read(tournamentOverrideControllerProvider.notifier);
      notifier
        ..addSet(maxSets: 3)
        ..removeSet()
        ..removeSet()
        ..removeSet(); // floor at 1
      expect(c.read(tournamentOverrideControllerProvider).sets, hasLength(1));
    });

    test('setReason trims to reasonMax characters', () {
      final c = _container();
      addTearDown(c.dispose);
      final notifier = c.read(tournamentOverrideControllerProvider.notifier);
      final tooLong = 'x' * (TournamentOverrideController.reasonMax + 50);
      notifier.setReason(tooLong);
      expect(
        c.read(tournamentOverrideControllerProvider).reason.length,
        TournamentOverrideController.reasonMax,
      );
    });

    test('isScoreDecisive flips once one side reaches setsToWin', () {
      final c = _container();
      addTearDown(c.dispose);
      final notifier = c.read(tournamentOverrideControllerProvider.notifier);
      expect(notifier.isScoreDecisive(2), isFalse);
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
      expect(notifier.isScoreDecisive(2), isTrue);
    });

    test('submit forwards trimmed reason and scores to the remote', () async {
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
        )
        ..setReason('  Schiedsrichter-Entscheidung  ');
      await notifier.submit(const TournamentMatchId('m-1'), setsToWin: 2);
      expect(remote.lastCall, isNotNull);
      expect(remote.lastCall!.id, const TournamentMatchId('m-1'));
      expect(remote.lastCall!.reason, 'Schiedsrichter-Entscheidung');
      expect(remote.lastCall!.scores, hasLength(2));
      expect(remote.lastCall!.scores.first.winner, SetWinner.teamA);
    });

    test('submit refuses when reason is blank or score is undecided', () async {
      final remote = _CapturingRemote();
      final c = _container(remote: remote);
      addTearDown(c.dispose);
      final notifier = c.read(tournamentOverrideControllerProvider.notifier);
      notifier.setReason('   ');
      await expectLater(
        notifier.submit(const TournamentMatchId('m-1'), setsToWin: 2),
        throwsA(isA<StateError>()),
      );
      expect(remote.lastCall, isNull);
    });
  });
}
