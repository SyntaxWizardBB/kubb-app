// Integration-flavoured widget test that exercises the M1 happy path
// (4-player round-robin, all matches finalised through consensus) plus
// the conflict-and-override sibling. Drives the use-case via the
// `tournamentActionsProvider` + `tournamentActionsProvider`
// surfaces wired to a [FakeTournamentRemote], then pumps the
// standings screen at the end to confirm the read model is intact.
//
// The router does not expose tournament routes yet (M1-W4-B), so the
// test embeds the standings screen behind a tiny `GoRouter` rather
// than walking real navigation. The provider-level assertions cover
// the business outcome; the standings render is the e2e smoke check.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_standings_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

const _userA = UserId('user-a');
const _userB = UserId('user-b');
const _userC = UserId('user-c');
const _userD = UserId('user-d');
const _organizer = UserId('user-org');

ProviderContainer _container({
  required FakeTournamentRemote remote,
  required UserId currentUser,
}) {
  final c = ProviderContainer(
    overrides: [
      tournamentRemoteProvider.overrideWithValue(remote),
      currentUserIdProvider.overrideWith((_) => currentUser.value),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

SetScore _agreedSet({required SetWinner winner}) {
  // A clean 5:3 (or 3:5) with the king dropped by the winner. Identical
  // bytes from both teams trigger the consensus-finalised path.
  return SetScore(
    basekubbsKnockedByA: winner == SetWinner.teamA ? 5 : 3,
    basekubbsKnockedByB: winner == SetWinner.teamB ? 5 : 3,
    winner: winner,
  );
}

Future<TournamentParticipantId> _registerAs(
  FakeTournamentRemote remote,
  ProviderContainer c,
  UserId user,
  TournamentId tid,
) async {
  remote.currentUser = user;
  return c.read(tournamentActionsProvider).registerSingle(tid);
}

Future<void> _submitAs(
  FakeTournamentRemote remote,
  TournamentActions actions,
  UserId user,
  TournamentMatchId matchId, {
  required int round,
  required List<SetScore> sets,
}) async {
  remote.currentUser = user;
  await actions.proposeSetScores(
    matchId: matchId,
    consensusRound: round,
    setScores: sets,
  );
}

Future<void> _pumpStandings(
  WidgetTester tester, {
  required FakeTournamentRemote remote,
  required UserId currentUser,
  required TournamentId tournamentId,
}) async {
  final router = GoRouter(
    initialLocation: '/tournament/${tournamentId.value}/standings',
    routes: <RouteBase>[
      GoRoute(
        path: '/tournament/:id/standings',
        builder: (_, s) => TournamentStandingsScreen(
          tournamentId: s.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/tournament/:id/matches',
        builder: (_, _) => const Scaffold(body: Text('matches')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(remote),
        currentUserIdProvider.overrideWith((_) => currentUser.value),
        // The standings screen subscribes to the per-tournament channel as
        // its realtime anchor (W1-T14); reuse the remote's fake transport.
        realtimeChannelProvider.overrideWithValue(remote.realtime),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: KubbTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '4-player round-robin happy path: create → register → start → submit → finalize',
    (tester) async {
      final remote = FakeTournamentRemote(initialUser: _organizer);
      final c = _container(remote: remote, currentUser: _organizer);
      final actions = c.read(tournamentActionsProvider);

      // Step 1: organizer creates a 4-player BO1 round-robin tournament.
      final draft = TournamentConfigDraft(
        displayName: 'M1 Smoke RR',
        minParticipants: 4,
        maxParticipants: 4,
        setsToWin: 1,
        maxSets: 1,
        // W1 required Stammdaten (Spasstournier = no club).
        clubChoiceMade: true,
        location: 'Esp',
        venueAddress: 'Sportplatz Esp',
        eventStartsAt: DateTime(2026, 8, 1, 10),
        registrationClosesAt: DateTime(2026, 7, 25, 23, 59),
        checkinUntil: DateTime(2026, 8, 1, 9, 30),
      );
      final tid = await actions.createTournament(draft);

      // Step 2 + 3: publish, open registration.
      await actions.publish(tid);
      await actions.openRegistration(tid);

      // Step 4: four distinct users register as singles.
      final pA = await _registerAs(remote, c, _userA, tid);
      final pB = await _registerAs(remote, c, _userB, tid);
      final pC = await _registerAs(remote, c, _userC, tid);
      final pD = await _registerAs(remote, c, _userD, tid);

      // Step 5: organizer confirms all four.
      remote.currentUser = _organizer;
      for (final p in <TournamentParticipantId>[pA, pB, pC, pD]) {
        await actions.confirmRegistration(p);
      }

      // Step 6: organizer closes registration and starts the tournament.
      await actions.closeRegistration(tid);
      await actions.startTournament(tid);

      // Step 7: a 4-player round-robin yields n*(n-1)/2 = 6 matches.
      final matches = await remote.listMatchesForTournament(tid);
      expect(matches, hasLength(6),
          reason: '4-player RR must produce 6 unique pairings');
      expect(
        matches.every((m) => m.status == TournamentMatchStatus.scheduled),
        isTrue,
      );
      expect(
        matches.every((m) => m.participantB != null),
        isTrue,
        reason: 'even-N round robin has no BYE slots',
      );

      // Step 8: both participants of every match submit identical scores.
      // Deterministic outcome: participantA wins every pairing — keeps the
      // final standings ordering independent of the pairing schedule.
      final userByPid = <TournamentParticipantId, UserId>{
        pA: _userA,
        pB: _userB,
        pC: _userC,
        pD: _userD,
      };
      final matchActions = c.read(tournamentActionsProvider);
      final aWinsSets = <SetScore>[_agreedSet(winner: SetWinner.teamA)];
      for (final m in matches) {
        await _submitAs(remote, matchActions, userByPid[m.participantA]!,
            m.matchId, round: 1, sets: aWinsSets);
        await _submitAs(remote, matchActions, userByPid[m.participantB]!,
            m.matchId, round: 1, sets: aWinsSets);
      }

      // Step 9: every match must now be finalised.
      final finalised = await remote.listMatchesForTournament(tid);
      expect(
        finalised.every((m) => m.status == TournamentMatchStatus.finalized),
        isTrue,
        reason: 'all six matches must be finalized after consensus',
      );
      for (final m in finalised) {
        expect(m.winnerParticipant, m.participantA,
            reason: 'team-A wins every set by construction');
        expect(m.finalScoreA, isNotNull);
        expect(m.finalScoreB, isNotNull);
        expect(m.finalScoreA! > m.finalScoreB!, isTrue);
      }

      // Step 10: standings provider must surface four ranked entries and
      // the screen must render them. We pump the screen as a smoke check
      // that the read-side wiring survives.
      final standings = await c.read(
        tournamentStandingsProvider(tid).future,
      );
      expect(standings, hasLength(4));
      expect(
        standings.map((s) => s.participantId).toSet(),
        <String>{pA.value, pB.value, pC.value, pD.value},
      );

      await _pumpStandings(
        tester,
        remote: remote,
        currentUser: _organizer,
        tournamentId: tid,
      );
      for (final p in <TournamentParticipantId>[pA, pB, pC, pD]) {
        expect(find.text(p.value), findsOneWidget);
      }
    },
  );

  testWidgets(
    'conflict and override path: 3 disagreeing attempts then organizer override',
    (tester) async {
      final remote = FakeTournamentRemote(initialUser: _organizer);
      final c = _container(remote: remote, currentUser: _organizer);
      final actions = c.read(tournamentActionsProvider);
      final matchActions = c.read(tournamentActionsProvider);

      // Minimal 2-player tournament so a single match is enough.
      final draft = TournamentConfigDraft(
        displayName: 'M1 Conflict',
        maxParticipants: 2,
        setsToWin: 1,
        maxSets: 1,
        // W1 required Stammdaten (Spasstournier = no club).
        clubChoiceMade: true,
        location: 'Esp',
        venueAddress: 'Sportplatz Esp',
        eventStartsAt: DateTime(2026, 8, 1, 10),
        registrationClosesAt: DateTime(2026, 7, 25, 23, 59),
        checkinUntil: DateTime(2026, 8, 1, 9, 30),
      );
      final tid = await actions.createTournament(draft);
      await actions.publish(tid);
      await actions.openRegistration(tid);
      final pA = await _registerAs(remote, c, _userA, tid);
      final pB = await _registerAs(remote, c, _userB, tid);
      remote.currentUser = _organizer;
      await actions.confirmRegistration(pA);
      await actions.confirmRegistration(pB);
      await actions.closeRegistration(tid);
      await actions.startTournament(tid);

      final matches = await remote.listMatchesForTournament(tid);
      expect(matches, hasLength(1));
      final match = matches.single;

      // Each round: A claims 5:3, B claims 3:5. Disagreement bumps the
      // round counter; the third disagreement flips to DISPUTED.
      final aFavoursA = <SetScore>[_agreedSet(winner: SetWinner.teamA)];
      final bFavoursB = <SetScore>[_agreedSet(winner: SetWinner.teamB)];
      Future<void> disagree(int round) async {
        await _submitAs(remote, matchActions, _userA, match.matchId,
            round: round, sets: aFavoursA);
        await _submitAs(remote, matchActions, _userB, match.matchId,
            round: round, sets: bFavoursB);
      }

      await disagree(1);
      var current = (await remote.getMatch(match.matchId))!;
      expect(current.consensusRound, 2);
      expect(current.status, TournamentMatchStatus.awaitingResults);

      await disagree(2);
      current = (await remote.getMatch(match.matchId))!;
      expect(current.consensusRound, 3);
      expect(current.status, TournamentMatchStatus.awaitingResults);

      await disagree(3);
      current = (await remote.getMatch(match.matchId))!;
      expect(current.status, TournamentMatchStatus.disputed,
          reason: 'third disagreement flips status to disputed');

      // Organizer override path: 2:1 wouldn't fit BO1, so we override
      // with a single decisive set + a Schiri reason.
      remote.currentUser = _organizer;
      await actions.organizerOverride(
        matchId: match.matchId,
        finalSetScores: <SetScore>[
          SetScore(
            basekubbsKnockedByA: 5,
            basekubbsKnockedByB: 2,
            winner: SetWinner.teamA,
          ),
        ],
        reason: 'Schiri-Entscheid',
      );
      current = (await remote.getMatch(match.matchId))!;
      expect(current.status, TournamentMatchStatus.overridden);
      expect(current.winnerParticipant, pA);
      expect(current.finalScoreA, isNotNull);
      expect(current.finalScoreA! > current.finalScoreB!, isTrue);

      // Reason rejection: empty reason must throw.
      expect(
        () => actions.organizerOverride(
          matchId: match.matchId,
          finalSetScores: <SetScore>[
            SetScore(
              basekubbsKnockedByA: 1,
              basekubbsKnockedByB: 0,
              winner: SetWinner.teamA,
            ),
          ],
          reason: '   ',
        ),
        throwsArgumentError,
      );
    },
  );
}
