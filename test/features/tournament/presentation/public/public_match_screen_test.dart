import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/public_tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_models.dart';
import 'package:kubb_app/features/tournament/presentation/public/public_match_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

// M1: the public spectator match view must render the REAL display names
// of both sides (resolved via the parent tournament roster) and fall back
// to the localized "Unbekannt" — never a raw UUID substring or 'A'/'B'.

PublicMatchDetail _match({
  String aId = 'alpha-uuid-1111',
  String? bId = 'beta-uuid-2222',
}) {
  return PublicMatchDetail(
    matchId: const TournamentMatchId('m-1'),
    tournamentId: const TournamentId('t-1'),
    roundNumber: 1,
    matchNumberInRound: 1,
    participantA: TournamentParticipantId(aId),
    participantB: bId == null ? null : TournamentParticipantId(bId),
    status: TournamentMatchStatus.finalized,
    consensusRound: 1,
    finalScoreA: 2,
    finalScoreB: 1,
  );
}

PublicTournamentDetail _detail({required List<PublicRosterEntry> roster}) {
  return PublicTournamentDetail(
    tournament: const PublicTournamentHeader(
      tournamentId: TournamentId('t-1'),
      displayName: 'Sommer-Cup',
      teamSize: 1,
      format: TournamentFormat.singleElimination,
      scoring: TournamentScoring.ekc,
      status: TournamentStatus.live,
      matchFormatConfig: <String, Object?>{},
    ),
    matches: const <PublicMatchDetail>[],
    roster: roster,
    participantCount: roster.length,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required PublicMatchDetail match,
  required PublicTournamentDetail detail,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        publicMatchDetailProvider(match.matchId)
            .overrideWith((ref) async => match),
        publicTournamentDetailProvider(match.tournamentId)
            .overrideWith((ref) async => detail),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: KubbTheme.light(),
        home: PublicMatchScreen(matchId: match.matchId.value),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows the real display names of both sides via the roster',
      (tester) async {
    await _pump(
      tester,
      match: _match(),
      detail: _detail(roster: const [
        PublicRosterEntry(
          slotId: null,
          participantId: 'alpha-uuid-1111',
          slotIndex: 0,
          displayName: 'Alice',
        ),
        PublicRosterEntry(
          slotId: null,
          participantId: 'beta-uuid-2222',
          slotIndex: 0,
          displayName: 'Bob',
        ),
      ]),
    );
    expect(find.text('Alice gegen Bob'), findsOneWidget);
    // No raw UUID substring and no generic placeholder.
    expect(find.textContaining('alpha-'), findsNothing);
    expect(find.textContaining('beta-'), findsNothing);
    expect(find.text('Unbekannt'), findsNothing);
  });

  testWidgets('falls back to Unbekannt instead of a UUID substring',
      (tester) async {
    // Roster has no entry for side B -> the old code showed `beta-u`;
    // now it must show the localized "Unbekannt".
    await _pump(
      tester,
      match: _match(),
      detail: _detail(roster: const [
        PublicRosterEntry(
          slotId: null,
          participantId: 'alpha-uuid-1111',
          slotIndex: 0,
          displayName: 'Alice',
        ),
      ]),
    );
    expect(find.text('Alice gegen Unbekannt'), findsOneWidget);
    expect(find.textContaining('beta-'), findsNothing);
  });

  testWidgets('BYE match shows the real name + Freilos header', (tester) async {
    await _pump(
      tester,
      match: _match(bId: null),
      detail: _detail(roster: const [
        PublicRosterEntry(
          slotId: null,
          participantId: 'alpha-uuid-1111',
          slotIndex: 0,
          displayName: 'Alice',
        ),
      ]),
    );
    expect(find.text('Freilos'), findsOneWidget);
    expect(find.textContaining('gegen'), findsNothing);
  });
}
