import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/team/application/team_detail_provider.dart';
import 'package:kubb_app/features/team/application/team_list_provider.dart';
import 'package:kubb_app/features/team/data/team_models.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/presentation/register_team_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

// W2-T6 / R19-F-01 / FR-REG-12: deckt das Pool-Rendering im
// `RosterCompositionWidget` ab, nachdem das `teamDetailProvider` an
// `RegisterTeamScreen` durchgereicht ist. Ohne Verdrahtung blieb das
// Picker-Panel leer (vgl. ehemals `pool: const []`).
const _tournamentId = TournamentId('t-1');
const _teamId = TeamId('team-1');

TournamentDetail _detail({int teamSize = 3}) {
  return TournamentDetail(
    tournament: TournamentDetailHeader(
      tournamentId: _tournamentId.value,
      displayName: 'Sommer-Cup',
      createdByUserId: 'u-creator',
      teamSize: teamSize,
      minParticipants: 2,
      maxParticipants: 8,
      format: TournamentFormat.roundRobin,
      scoring: TournamentScoring.ekc,
      matchFormatConfig: const <String, Object?>{
        'sets_to_win': 2,
        'max_sets': 3,
      },
      tiebreakerOrder: const ['pts', 'sets'],
      byePoints: null,
      forfeitPoints: null,
      status: TournamentStatus.registrationOpen,
      publishedAt: null,
      startedAt: null,
      completedAt: null,
    ),
    participants: const [],
    matches: const [],
    auditTail: const [],
  );
}

TeamWire _team() => TeamWire(
      id: _teamId.value,
      displayName: 'Team Eins',
      leagueMembership: 'B',
      createdAt: DateTime.utc(2026),
    );

Map<String, dynamic> _teamPayload(List<Map<String, dynamic>> pool) {
  return <String, dynamic>{
    'team_id': _teamId.value,
    'display_name': 'Team Eins',
    'league_membership': 'B',
    'pool': pool,
    'guests': const <Map<String, dynamic>>[],
  };
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Map<String, dynamic>> pool,
}) async {
  final router = GoRouter(
    initialLocation: '/tournament/${_tournamentId.value}/register',
    routes: [
      GoRoute(
        path: '/tournament/:id/register',
        builder: (_, _) =>
            const RegisterTeamScreen(tournamentId: _tournamentId),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentDetailProvider(_tournamentId)
            .overrideWith((_) async => _detail()),
        teamListProvider.overrideWith((_) async => <TeamWire>[_team()]),
        teamDetailProvider(_teamId)
            .overrideWith((_) async => _teamPayload(pool)),
      ],
      child: MaterialApp.router(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'pool members are rendered in the roster picker once a team is selected',
    (tester) async {
      await _pump(tester, pool: [
        {
          'membership_id': 'mem-1',
          'user_id': 'alice',
          'joined_at': '2026-01-01T00:00:00Z',
        },
        {
          'membership_id': 'mem-2',
          'user_id': 'bob',
          'joined_at': '2026-01-01T00:00:00Z',
        },
        {
          'membership_id': 'mem-3',
          'user_id': 'carol',
          'joined_at': '2026-01-01T00:00:00Z',
        },
      ]);

      // Team auswaehlen: Dropdown via Label-Text oeffnen, dann Eintrag tappen.
      await tester.tap(find.text('Team'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Team Eins').last);
      await tester.pumpAndSettle();

      // Alle drei Pool-Members tauchen als Picker-Eintraege auf.
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('carol'), findsOneWidget);

      // FR-REG-12: User kann einen Pool-Eintrag antippen und im
      // Slot-Dialog einen Slot waehlen.
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();
      expect(find.text('Slot wählen'), findsOneWidget);
      await tester.tap(find.text('Slot 1'));
      await tester.pumpAndSettle();

      // Die Zuweisung erscheint im Slot-Panel.
      expect(find.text('alice'), findsWidgets);
    },
  );

  testWidgets('shows a loading indicator while the team detail is pending',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/tournament/${_tournamentId.value}/register',
      routes: [
        GoRoute(
          path: '/tournament/:id/register',
          builder: (_, _) =>
              const RegisterTeamScreen(tournamentId: _tournamentId),
        ),
      ],
    );

    final completer = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tournamentDetailProvider(_tournamentId)
              .overrideWith((_) async => _detail()),
          teamListProvider.overrideWith((_) async => <TeamWire>[_team()]),
          teamDetailProvider(_teamId)
              .overrideWith((_) async => completer.future),
        ],
        child: MaterialApp.router(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team Eins').last);
    // Ohne `pumpAndSettle` — das Future ist noch offen, der Loader laeuft.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(_teamPayload(const <Map<String, dynamic>>[]));
    await tester.pumpAndSettle();
  });
}
