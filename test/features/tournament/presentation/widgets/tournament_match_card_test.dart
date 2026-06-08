import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_match_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

// CF3 / K08: the match card must show the server-projected display name
// (single -> player nickname, team -> team name) and only fall back to
// the nameFor resolver when the server shipped no name.
TournamentMatchRef _match({
  String? aName,
  String? bName,
  String aId = 'aaaa1111',
  String bId = 'bbbb2222',
}) {
  return TournamentMatchRef(
    matchId: const TournamentMatchId('m-1'),
    tournamentId: const TournamentId('t-1'),
    roundNumber: 1,
    matchNumberInRound: 1,
    participantA: TournamentParticipantId(aId),
    participantB: TournamentParticipantId(bId),
    participantADisplayName: aName,
    participantBDisplayName: bName,
    status: TournamentMatchStatus.scheduled,
    consensusRound: 1,
  );
}

Future<void> _pump(WidgetTester tester, TournamentMatchRef match) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: KubbTheme.light(),
      home: Scaffold(
        body: TournamentMatchCard(
          match: match,
          // M1: the card resolves both sides through the central
          // [ParticipantName] helper — no per-call-site name resolver.
          onTap: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'single tournament: shows the player nickname from the server name',
      (tester) async {
    await _pump(tester, _match(aName: 'SingleAlice', bName: 'CaptainBob'));
    expect(find.text('SingleAlice'), findsOneWidget);
    expect(find.text('CaptainBob'), findsOneWidget);
    // No generic 'A'/'B' placeholder and no raw id is rendered.
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsNothing);
    expect(find.text('aaaa1111'), findsNothing);
  });

  testWidgets('team tournament: shows the team name from the server name',
      (tester) async {
    await _pump(
      tester,
      _match(aName: 'Die Kubb-Kanonen', bName: 'Holzwürfel United'),
    );
    expect(find.text('Die Kubb-Kanonen'), findsOneWidget);
    expect(find.text('Holzwürfel United'), findsOneWidget);
    expect(find.text('Team A'), findsNothing);
    expect(find.text('Team B'), findsNothing);
  });

  testWidgets(
      'falls back to the localized Unbekannt when the server name is absent',
      (tester) async {
    await _pump(tester, _match());
    // Both server names null -> both resolve to the localized "Unbekannt"
    // fallback, never 'A'/'B' or a raw UUID substring.
    expect(find.text('Unbekannt'), findsNWidgets(2));
    expect(find.text('aaaa1111'), findsNothing);
    expect(find.text('bbbb2222'), findsNothing);
  });

  testWidgets('bye row keeps the localized BYE label, side A uses the name',
      (tester) async {
    const bye = TournamentMatchRef(
      matchId: TournamentMatchId('m-2'),
      tournamentId: TournamentId('t-1'),
      roundNumber: 1,
      matchNumberInRound: 1,
      participantA: TournamentParticipantId('aaaa1111'),
      participantB: null,
      participantADisplayName: 'SingleAlice',
      status: TournamentMatchStatus.scheduled,
      consensusRound: 1,
    );
    await _pump(tester, bye);
    expect(find.text('SingleAlice'), findsOneWidget);
    // BYE side shows the localized BYE label, never a second placeholder.
    expect(find.text('BYE'), findsOneWidget);
  });
}
