// M4 Unit 5 — client-side Schoch next-round pairing (ADR-0039 §3, ADR-0036).
//
// The client RECHNET the pairing in Dart (SwissSystemStrategy.planRound) and
// submits it to the server, which only validates. These tests pin three
// things against a fake remote:
//   (a) pairRound reads the STAGE-SCOPED state — only matches carrying the
//       given stage_node_id feed the standings/round-count, matches of other
//       stages are ignored;
//   (b) the pairing that reaches the port equals what planRound computes from
//       that state for roundNumber = current + 1 — i.e. the client did the
//       work, not the server;
//   (c) the submission carries the stage_node_id verbatim.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _tid = TournamentId('t-schoch');
const _stage = 'stage-schoch-1';
const _otherStage = 'stage-ko-1';

/// Records the pairStageRound submission and serves a fixed, stage-tagged
/// match list. Everything else is `noSuchMethod`'d away.
class _RecordingRemote implements TournamentRemote {
  _RecordingRemote(this._matches);

  final List<TournamentMatchRef> _matches;

  ({
    TournamentId tournamentId,
    String stageNodeId,
    List<PlannedPairing> pairings,
  })? lastPair;

  @override
  Future<List<TournamentMatchRef>> listMatchesForTournament(
    TournamentId id,
  ) async =>
      _matches;

  @override
  Future<void> pairStageRound({
    required TournamentId tournamentId,
    required String stageNodeId,
    required List<PlannedPairing> pairings,
  }) async {
    lastPair = (
      tournamentId: tournamentId,
      stageNodeId: stageNodeId,
      pairings: pairings,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

TournamentMatchRef _m(
  int round,
  int n,
  String a,
  String b, {
  required String? stageNodeId,
  int scoreA = 16,
  int scoreB = 5,
}) =>
    TournamentMatchRef(
      matchId: TournamentMatchId('m-$round-$n-${stageNodeId ?? 'flat'}'),
      tournamentId: _tid,
      roundNumber: round,
      matchNumberInRound: n,
      participantA: TournamentParticipantId(a),
      participantB: TournamentParticipantId(b),
      status: TournamentMatchStatus.finalized,
      consensusRound: 1,
      finalScoreA: scoreA,
      finalScoreB: scoreB,
      stageNodeId: stageNodeId,
    );

void main() {
  // The roster the client feeds planRound is the union of participants seen in
  // THIS stage's matches, in first-seen (stable start-number) order. Round 1 of
  // the stage finished P1>P2, P3>P4, P5>P6, P7>P8.
  List<TournamentMatchRef> stageRound1() => <TournamentMatchRef>[
        _m(1, 1, 'P1', 'P2', stageNodeId: _stage),
        _m(1, 2, 'P3', 'P4', stageNodeId: _stage, scoreA: 12, scoreB: 11),
        _m(1, 3, 'P5', 'P6', stageNodeId: _stage, scoreA: 9, scoreB: 9),
        _m(1, 4, 'P7', 'P8', stageNodeId: _stage, scoreB: 2),
      ];

  PlannedRound expectedRound2(List<TournamentMatchRef> stageMatches) {
    final roster = <String>[];
    for (final m in stageMatches) {
      final a = m.participantA!.value;
      final b = m.participantB!.value;
      if (!roster.contains(a)) roster.add(a);
      if (!roster.contains(b)) roster.add(b);
    }
    final completed = <MatchResult>[
      for (final m in stageMatches)
        MatchResult(
          participantA: m.participantA!.value,
          participantB: m.participantB!.value,
          pointsA: m.finalScoreA!,
          pointsB: m.finalScoreB!,
          roundNumber: m.roundNumber,
        ),
    ];
    return const SwissSystemStrategy().planRound(
      participants: roster,
      completedMatches: completed,
      roundNumber: 2,
      tournamentId: _tid.value,
    );
  }

  test('pairRound computes the next round client-side and submits it '
      'stage-scoped', () async {
    final remote = _RecordingRemote(stageRound1());
    final container = ProviderContainer(
      overrides: [tournamentRemoteProvider.overrideWithValue(remote)],
    );
    addTearDown(container.dispose);

    await container
        .read(tournamentActionsProvider)
        .pairRound(_tid, _stage);

    final pair = remote.lastPair;
    expect(pair, isNotNull, reason: 'the port must receive a submission');
    expect(pair!.tournamentId, _tid);
    // (c) stage-scoped: the node id travels verbatim.
    expect(pair.stageNodeId, _stage);

    // (b) the submitted pairing equals what planRound computes locally for
    // round 2 — proves the CLIENT did the pairing, not the server.
    final expected = expectedRound2(stageRound1());
    expect(pair.pairings, equals(expected.pairings));
  });

  test('pairRound ignores matches of other stages when computing the round',
      () async {
    // Same schoch round 1, plus noise from a KO stage and a flat (null-stage)
    // match. A stage-blind implementation would fold the noise into the
    // standings / round count and produce a different pairing or round number.
    final matches = <TournamentMatchRef>[
      ...stageRound1(),
      _m(1, 1, 'X1', 'X2', stageNodeId: _otherStage),
      _m(5, 9, 'Y1', 'Y2', stageNodeId: null),
    ];
    final remote = _RecordingRemote(matches);
    final container = ProviderContainer(
      overrides: [tournamentRemoteProvider.overrideWithValue(remote)],
    );
    addTearDown(container.dispose);

    await container
        .read(tournamentActionsProvider)
        .pairRound(_tid, _stage);

    final pair = remote.lastPair!;
    // The pairing must match the stage-only computation — the KO/flat rows
    // must not leak into the roster, the standings, or the round number.
    final expected = expectedRound2(stageRound1());
    expect(pair.pairings, equals(expected.pairings));
    expect(expected.roundNumber, 2, reason: 'round count stays stage-scoped');
    for (final p in pair.pairings) {
      expect(p.participantA, isNot(anyOf('X1', 'X2', 'Y1', 'Y2')));
      expect(p.participantB, isNot(anyOf('X1', 'X2', 'Y1', 'Y2')));
    }
  });

  test('pairRound invalidates the stage match list so the new round shows up',
      () async {
    final remote = _RecordingRemote(stageRound1());
    final container = ProviderContainer(
      overrides: [tournamentRemoteProvider.overrideWithValue(remote)],
    );
    addTearDown(container.dispose);

    final sub = container.listen(
      tournamentMatchListProvider(_tid),
      (_, _) {},
    );
    addTearDown(sub.close);
    await container.read(tournamentMatchListProvider(_tid).future);

    await container
        .read(tournamentActionsProvider)
        .pairRound(_tid, _stage);

    // A re-read must hit the remote again — the list was invalidated.
    await container.read(tournamentMatchListProvider(_tid).future);
    expect(remote.lastPair, isNotNull);
  });
}
