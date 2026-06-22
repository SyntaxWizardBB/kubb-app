import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

class _StandingsRemote implements TournamentRemote {
  _StandingsRemote({required this.format});

  final TournamentFormat format;

  @override
  Future<List<TournamentMatchRef>> listMatchesForTournament(
    TournamentId id,
  ) async {
    return [
      // 'a' wins a regular match against 'b', and 'c' draws a bye.
      TournamentMatchRef(
        matchId: const TournamentMatchId('m-1'),
        tournamentId: id,
        roundNumber: 1,
        matchNumberInRound: 1,
        participantA: const TournamentParticipantId('a'),
        participantB: const TournamentParticipantId('b'),
        status: TournamentMatchStatus.finalized,
        consensusRound: 0,
        finalScoreA: 6,
        finalScoreB: 0,
      ),
      TournamentMatchRef(
        matchId: const TournamentMatchId('m-2'),
        tournamentId: id,
        roundNumber: 1,
        matchNumberInRound: 2,
        participantA: const TournamentParticipantId('c'),
        participantB: null,
        status: TournamentMatchStatus.finalized,
        consensusRound: 0,
      ),
    ];
  }

  @override
  Future<TournamentDetail?> getTournamentDetail(TournamentId id) async {
    return TournamentDetail(
      tournament: TournamentDetailHeader(
        tournamentId: id.value,
        displayName: 'Test-Cup',
        createdByUserId: 'u-creator',
        clubId: null,
        teamSize: 1,
        maxTeamSize: 1,
        minParticipants: 2,
        maxParticipants: 8,
        format: format,
        scoring: TournamentScoring.ekc,
        matchFormatConfig: const <String, Object?>{},
        tiebreakerOrder: const <String>[],
        byePoints: 0,
        forfeitPoints: 0,
        status: TournamentStatus.live,
        publishedAt: null,
        startedAt: null,
        completedAt: null,
      ),
      participants: const <TournamentParticipant>[],
      matches: const <TournamentMatchRef>[],
      auditTail: const <TournamentAuditEvent>[],
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

int _byeTotalFor(List<ParticipantStats> rows) =>
    rows.firstWhere((s) => s.participantId == 'c').totalPoints;

Future<List<ParticipantStats>> _standings(TournamentFormat format) async {
  final c = ProviderContainer(
    overrides: [
      tournamentRemoteProvider
          .overrideWithValue(_StandingsRemote(format: format)),
    ],
  );
  addTearDown(c.dispose);
  return c.read(tournamentStandingsProvider(const TournamentId('t-1')).future);
}

void main() {
  group('tournamentStandingsProvider bye wiring', () {
    test('a Schoch bye player gains 16 points', () async {
      final rows = await _standings(TournamentFormat.schoch);
      expect(_byeTotalFor(rows), equals(16));
    });

    test('a Schoch-then-KO bye player gains 16 points', () async {
      final rows = await _standings(TournamentFormat.schochThenKo);
      expect(_byeTotalFor(rows), equals(16));
    });

    test('a round-robin bye player gains 0 points', () async {
      final rows = await _standings(TournamentFormat.roundRobin);
      expect(_byeTotalFor(rows), equals(0));
    });
  });
}
