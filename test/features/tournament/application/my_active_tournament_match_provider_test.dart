import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/my_active_match_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// P5-C (ADR-0032 §7): `myActiveTournamentMatchProvider` folds the existing
/// per-tournament `myActiveMatchProvider` over the caller's registrations
/// and picks the most urgent open tournament match. Pure container test —
/// both sources are overridden, so no network/realtime is touched.
TournamentSummaryRef _tournament(
  String id, {
  TournamentStatus status = TournamentStatus.live,
}) =>
    TournamentSummaryRef(
      tournamentId: TournamentId(id),
      displayName: 'Turnier $id',
      format: TournamentFormat.roundRobin,
      status: status,
      startedAt: null,
      completedAt: null,
      participantCount: 8,
    );

MyTournamentRegistration _registration(
  TournamentSummaryRef tournament, {
  TournamentParticipantStatus status = TournamentParticipantStatus.approved,
}) =>
    MyTournamentRegistration(
      tournament: tournament,
      participantId: TournamentParticipantId('p-${tournament.tournamentId.value}'),
      status: status,
    );

MyActiveMatch _activeMatch(
  String tournamentId,
  String matchId,
  TournamentMatchStatus status, {
  int roundNumber = 1,
  int matchNumberInRound = 1,
}) =>
    MyActiveMatch(
      match: TournamentMatchRef(
        matchId: TournamentMatchId(matchId),
        tournamentId: TournamentId(tournamentId),
        roundNumber: roundNumber,
        matchNumberInRound: matchNumberInRound,
        participantA: TournamentParticipantId('p-$tournamentId'),
        participantB: const TournamentParticipantId('p-opponent'),
        status: status,
        consensusRound: 0,
      ),
      pitchLabel: '$matchNumberInRound',
      opponentName: 'Gegner $tournamentId',
    );

ProviderContainer _container({
  required List<MyTournamentRegistration> registrations,
  Map<String, MyActiveMatch?> activeByTournament = const {},
}) {
  final container = ProviderContainer(
    overrides: [
      myTournamentRegistrationsProvider.overrideWith(
        (ref) async => registrations,
      ),
      myActiveMatchProvider.overrideWith(
        (ref, tournamentId) => AsyncValue<MyActiveMatch?>.data(
          activeByTournament[tournamentId.value],
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<AsyncValue<MyActiveTournamentMatch?>> _read(
  ProviderContainer container,
) async {
  final sub = container.listen(myActiveTournamentMatchProvider, (_, _) {});
  addTearDown(sub.close);
  // Let the registrations FutureProvider resolve.
  await container.read(myTournamentRegistrationsProvider.future);
  await Future<void>.delayed(Duration.zero);
  return sub.read();
}

void main() {
  group('myActiveTournamentMatchProvider', () {
    test(
        'cross-tournament: awaitingResults in tournament B beats scheduled '
        'in tournament A', () async {
      final tA = _tournament('t-a');
      final tB = _tournament('t-b');
      final container = _container(
        registrations: [_registration(tA), _registration(tB)],
        activeByTournament: {
          't-a': _activeMatch('t-a', 'm-a', TournamentMatchStatus.scheduled),
          't-b': _activeMatch(
            't-b',
            'm-b',
            TournamentMatchStatus.awaitingResults,
            roundNumber: 3,
          ),
        },
      );

      final result = await _read(container);

      expect(result.hasValue, isTrue);
      final pick = result.value;
      expect(pick, isNotNull);
      expect(pick!.tournament.tournamentId.value, 't-b',
          reason: 'awaitingResults outranks scheduled even in a later round');
      expect(pick.active.match.matchId.value, 'm-b');
    });

    test(
        'equal urgency across tournaments breaks deterministically on the '
        'match id', () async {
      final tA = _tournament('t-a');
      final tB = _tournament('t-b');
      final container = _container(
        registrations: [_registration(tB), _registration(tA)],
        activeByTournament: {
          't-a': _activeMatch('t-a', 'm-1', TournamentMatchStatus.scheduled),
          't-b': _activeMatch('t-b', 'm-2', TournamentMatchStatus.scheduled),
        },
      );

      final result = await _read(container);

      expect(result.value?.active.match.matchId.value, 'm-1',
          reason: 'lexicographically smaller match id wins the tie');
    });

    test('no registrations → data(null)', () async {
      final container = _container(registrations: const []);

      final result = await _read(container);

      expect(result, const AsyncValue<MyActiveTournamentMatch?>.data(null));
    });

    test(
        'registered but no open match anywhere (terminal/BYE only) → '
        'data(null)', () async {
      final tA = _tournament('t-a');
      final tB = _tournament('t-b');
      final container = _container(
        registrations: [_registration(tA), _registration(tB)],
        // The per-tournament provider already maps terminal-only / BYE-only
        // match lists to null — modelled here as null per tournament.
        activeByTournament: const {'t-a': null, 't-b': null},
      );

      final result = await _read(container);

      expect(result.hasValue, isTrue);
      expect(result.value, isNull);
    });

    test('withdrawn and non-live registrations are not considered', () async {
      final withdrawn = _tournament('t-a');
      final upcoming =
          _tournament('t-b', status: TournamentStatus.registrationOpen);
      final container = _container(
        registrations: [
          _registration(
            withdrawn,
            status: TournamentParticipantStatus.withdrawn,
          ),
          _registration(upcoming),
        ],
        activeByTournament: {
          // Would be a hit if the fold (incorrectly) considered them.
          't-a': _activeMatch(
            't-a',
            'm-a',
            TournamentMatchStatus.awaitingResults,
          ),
          't-b': _activeMatch('t-b', 'm-b', TournamentMatchStatus.scheduled),
        },
      );

      final result = await _read(container);

      expect(result.hasValue, isTrue);
      expect(result.value, isNull);
    });
  });
}
