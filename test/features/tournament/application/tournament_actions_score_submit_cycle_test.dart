import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/application/outbox_flusher.dart';
import 'package:kubb_app/core/application/outbox_flusher_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Regression for the score-submit provider cycle: submitting a result
/// through [TournamentActions.proposeSetScores] must not raise a Riverpod
/// circular-dependency error.
///
/// The cycle was `outboxFlusherProvider` watching `tournamentRemoteProvider`
/// (flusher → remote) while the repository kicked off the flush from inside
/// its own `proposeSetScores` (remote → flusher). These two edges closed a
/// loop the moment a submit was made. The fix moves the flush trigger into
/// the application action, whose `ref` is outside that graph.
///
/// Both edges are reproduced here through provider overrides so the test
/// fails if the flush ever migrates back into the remote port.

class _FakeFlusher implements OutboxFlusher {
  int flushCalls = 0;

  @override
  Future<void> flushPending() async {
    flushCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Post-fix remote: persists the submission and returns. It deliberately
/// does NOT touch [outboxFlusherProvider] — that is the contract the cycle
/// fix relies on.
class _AcyclicRemote implements TournamentRemote {
  int proposeCalls = 0;

  @override
  Future<void> proposeSetScores({
    required TournamentMatchId matchId,
    required int consensusRound,
    required List<SetScore> setScores,
  }) async {
    proposeCalls += 1;
  }

  @override
  Future<TournamentMatchRef?> getMatch(TournamentMatchId id) async => null;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Pre-fix remote: reproduces the bug by reading the flusher from inside the
/// submit, closing the loop. Used only to prove the wiring under test
/// actually exposes the cycle.
class _CyclicRemote implements TournamentRemote {
  _CyclicRemote(this._ref);

  final Ref _ref;

  @override
  Future<void> proposeSetScores({
    required TournamentMatchId matchId,
    required int consensusRound,
    required List<SetScore> setScores,
  }) async {
    await _ref.read(outboxFlusherProvider).flushPending();
  }

  @override
  Future<TournamentMatchRef?> getMatch(TournamentMatchId id) async => null;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  const matchId = TournamentMatchId('m-submit');
  final setScores = <SetScore>[
    SetScore(
      basekubbsKnockedByA: 6,
      basekubbsKnockedByB: 0,
      winner: SetWinner.teamA,
    ),
  ];

  test(
      'proposeSetScores through the action does not raise a circular '
      'dependency error and triggers a flush', () async {
    final flusher = _FakeFlusher();
    final remote = _AcyclicRemote();
    final container = ProviderContainer(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(remote),
        // flusher → remote edge: the production flusher watches the remote.
        outboxFlusherProvider.overrideWith((ref) {
          ref.watch(tournamentRemoteProvider);
          return flusher;
        }),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(tournamentActionsProvider).proposeSetScores(
            matchId: matchId,
            consensusRound: 1,
            setScores: setScores,
          ),
      completes,
    );

    expect(remote.proposeCalls, 1);
    expect(flusher.flushCalls, 1,
        reason: 'the action must kick off the outbox flush');
  });

  test(
      'guard: routing the flush through the remote port closes the cycle '
      '(the regression this fix prevents)', () async {
    final flusher = _FakeFlusher();
    final container = ProviderContainer(
      overrides: [
        tournamentRemoteProvider.overrideWith(_CyclicRemote.new),
        outboxFlusherProvider.overrideWith((ref) {
          ref.watch(tournamentRemoteProvider);
          return flusher;
        }),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(tournamentActionsProvider).proposeSetScores(
            matchId: matchId,
            consensusRound: 1,
            setScores: setScores,
          ),
      // CircularDependencyError is not exported from the public riverpod
      // surface, so match on its runtime type name instead of the symbol.
      throwsA(
        isA<Error>().having(
          (e) => e.runtimeType.toString(),
          'runtimeType',
          'CircularDependencyError',
        ),
      ),
    );
  });
}
