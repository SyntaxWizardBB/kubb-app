import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/public_tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/public_link_share_service.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_models.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_realtime.dart';
import 'package:kubb_app/features/tournament/presentation/public/public_match_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Records the last shared link instead of invoking the system share sheet.
class _FakeLinkShareService extends PublicLinkShareService {
  String? sharedLink;
  String? sharedSubject;

  @override
  Future<LinkShareResult> shareLink(String link, {String? subject}) async {
    sharedLink = link;
    sharedSubject = subject;
    return LinkShareResult(kind: LinkShareKind.shared, link: link);
  }
}

// M1: the public spectator match view must render the REAL display names
// of both sides (resolved via the parent tournament roster) and fall back
// to the localized "Unbekannt" — never a raw UUID substring or 'A'/'B'.

PublicMatchDetail _match({
  String aId = 'alpha-uuid-1111',
  String? bId = 'beta-uuid-2222',
  TournamentMatchStatus status = TournamentMatchStatus.finalized,
  int? finalScoreA = 2,
  int? finalScoreB = 1,
  int? setsWonA,
  int? setsWonB,
}) {
  return PublicMatchDetail(
    matchId: const TournamentMatchId('m-1'),
    tournamentId: const TournamentId('t-1'),
    roundNumber: 1,
    matchNumberInRound: 1,
    participantA: TournamentParticipantId(aId),
    participantB: bId == null ? null : TournamentParticipantId(bId),
    status: status,
    consensusRound: 1,
    finalScoreA: finalScoreA,
    finalScoreB: finalScoreB,
    setsWonA: setsWonA,
    setsWonB: setsWonB,
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
  List<Object> extraOverrides = const <Object>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Object>[
        publicMatchDetailProvider(match.matchId)
            .overrideWith((ref) async => match),
        publicTournamentDetailProvider(match.tournamentId)
            .overrideWith((ref) async => detail),
        ...extraOverrides,
      ].cast(),
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

  // P1-4: a RUNNING match (awaiting_results) renders read-only with the
  // live set score (not '–:–') + status pill + real names. No edit/input
  // widgets exist on the public screen.
  testWidgets('renders a running match read-only with live set score',
      (tester) async {
    await _pump(
      tester,
      match: _match(
        status: TournamentMatchStatus.awaitingResults,
        finalScoreA: null,
        finalScoreB: null,
        setsWonA: 1,
        setsWonB: 1,
      ),
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
    // Real names resolved.
    expect(find.text('Alice gegen Bob'), findsOneWidget);
    // Live set tally is shown, NOT the placeholder.
    expect(find.text('1:1'), findsOneWidget);
    expect(find.text('–:–'), findsNothing);
    // Status pill present.
    expect(find.text('Warten'), findsOneWidget);
    // Read-only: no score-entry / consensus input widgets.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  // P1-6: tapping the share action hands the public /public/match/<id>
  // link to the share service.
  testWidgets('share action shares the correct /public/match/<id> link',
      (tester) async {
    final fake = _FakeLinkShareService();
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
      extraOverrides: [
        publicLinkShareServiceProvider.overrideWithValue(fake),
      ],
    );
    await tester.tap(find.byIcon(LucideIcons.share2));
    await tester.pump();
    expect(fake.sharedLink, isNotNull);
    expect(fake.sharedLink, endsWith('/public/match/m-1'));
  });

  // P1-5: an incoming broadcast event invalidates the match provider so the
  // screen re-fetches — no Timer.periodic, just the existing anon broadcast.
  testWidgets('broadcast event invalidates the match provider (re-fetch)',
      (tester) async {
    final events = StreamController<PublicTournamentEvent>.broadcast();
    addTearDown(events.close);
    var matchLoads = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Object>[
          publicMatchDetailProvider(const TournamentMatchId('m-1'))
              .overrideWith((ref) async {
            matchLoads += 1;
            return _match();
          }),
          publicTournamentDetailProvider(const TournamentId('t-1'))
              .overrideWith((ref) async => _detail(roster: const [
                    PublicRosterEntry(
                      slotId: null,
                      participantId: 'alpha-uuid-1111',
                      slotIndex: 0,
                      displayName: 'Alice',
                    ),
                  ])),
          publicTournamentEventsProvider(const TournamentId('t-1'))
              .overrideWith((ref) => events.stream),
        ].cast(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: KubbTheme.light(),
          home: const PublicMatchScreen(matchId: 'm-1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(matchLoads, 1);

    // Feed a match_status event over the existing anon broadcast topic.
    events.add(const PublicTournamentEvent(
      type: PublicTournamentEventType.matchStatus,
      tournamentId: TournamentId('t-1'),
      matchId: TournamentMatchId('m-1'),
      status: 'finalized',
    ));
    await tester.pump();
    await tester.pump();
    // Provider was invalidated -> the FutureProvider body ran again.
    expect(matchLoads, 2);
  });
}
