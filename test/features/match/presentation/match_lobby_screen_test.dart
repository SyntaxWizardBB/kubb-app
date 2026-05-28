// Widget test for Sprint B / W5-T2: the match lobby polished against
// `docs/design/ui_kits/app/MatchScreen.jsx` lobby tab. Asserts that the
// new KubbAppBar eyebrow + section-header + KubbButton variants are
// wired up correctly.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_lobby_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

MatchDetail _detail({
  MatchStatus status = MatchStatus.pendingInvites,
  String? createdBy = 'user-creator',
  List<MatchParticipant>? participants,
}) {
  final started = DateTime.utc(2026, 5, 24, 10);
  return MatchDetail(
    match: MatchDetailHeader(
      matchId: 'm-1',
      createdByUserId: createdBy,
      format: MatchFormat.bo3,
      scoring: MatchScoring.wins,
      status: status,
      startedAt: started,
      completedAt: null,
      currentRound: 1,
      settings: const <String, dynamic>{},
    ),
    teams: const [
      MatchTeam(teamId: 'A', displayName: null),
      MatchTeam(teamId: 'B', displayName: null),
    ],
    participants: participants ??
        [
          MatchParticipant(
            participantId: 'p-1',
            teamId: 'A',
            kind: MatchParticipantKind.inApp,
            userId: 'user-creator',
            nickname: 'Marc',
            invitationStatus: MatchInvitationStatus.accepted,
            joinedAt: started,
            respondedAt: started,
          ),
          MatchParticipant(
            participantId: 'p-2',
            teamId: 'B',
            kind: MatchParticipantKind.inApp,
            userId: 'user-other',
            nickname: 'Vinz',
            invitationStatus: MatchInvitationStatus.pending,
            joinedAt: started,
            respondedAt: null,
          ),
        ],
    ownProposal: null,
    auditTail: const [],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required MatchDetail detail,
  String? currentUserId = 'user-creator',
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/match/lobby/m-1',
    routes: [
      GoRoute(
        path: '/match/lobby/:id',
        builder: (_, state) =>
            MatchLobbyScreen(matchId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        matchDetailProvider('m-1').overrideWith((_) async => detail),
        // Polling provider runs a 1s Timer that would block pumpAndSettle
        // forever — stub it out for the widget test.
        matchPollingProvider('m-1').overrideWith((_) {}),
        currentUserIdProvider.overrideWith((_) => currentUserId),
      ],
      child: MaterialApp.router(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'lobby renders KubbAppBar with the Match · Lobby eyebrow and inset-card '
    'section header',
    (tester) async {
      await _pump(tester, detail: _detail());

      // AppBar migrated to KubbAppBar — the legacy raw AppBar is gone.
      expect(find.byType(KubbAppBar), findsOneWidget);

      // Eyebrow text (uppercased by the eyebrow widget) and title visible.
      // Two "Lobby" labels exist: the AppBar title and the
      // MatchStageIndicator pill (W5.1-A) — both expected.
      expect(find.text('MATCH · LOBBY'), findsOneWidget);
      expect(find.text('Lobby'), findsNWidgets(2));

      // Mitspieler section header in eyebrow style.
      expect(find.text('MITSPIELER'), findsOneWidget);

      // Both team panels rendered inside the inset card.
      expect(find.text('Team A'), findsOneWidget);
      expect(find.text('Team B'), findsOneWidget);
      // "Marc" / "Vinz" appear in both the new hero (team title) and
      // the legacy Mitspieler roster — assert presence, not uniqueness.
      expect(find.text('Marc'), findsAtLeastNWidgets(1));
      expect(find.text('Vinz'), findsAtLeastNWidgets(1));
    },
  );

  // -------------------------------------------------------------------
  // Sprint B / W5.1-B (BH-C-02): smoke tests for the three new sections
  // (`_LobbyHero`, `_H2HList`, `_MatchSetup`) from MatchScreen.jsx L48-87.
  // -------------------------------------------------------------------

  testWidgets(
    'lobby hero renders side-vs-vs-side layout with kickoff and vs label',
    (tester) async {
      await _pump(tester, detail: _detail());

      // Centre VS column.
      expect(find.text('vs.'), findsOneWidget);

      // Kickoff time formatted from MatchDetailHeader.startedAt.
      // The fixture uses UTC 2026-05-24 10:00 which, depending on the
      // host TZ, displays as a local HH:MM — just assert the format
      // shape via a regex.
      final clockFinder = find.byWidgetPredicate(
        (w) => w is Text &&
            w.data != null &&
            RegExp(r'^\d{2}:\d{2}$').hasMatch(w.data!),
      );
      expect(clockFinder, findsOneWidget);

      // Court fallback when settings.court is absent. The same label
      // also appears in the Match-Setup section below, so allow more
      // than one match.
      expect(find.text('Court —'), findsAtLeastNWidgets(1));

      // Form-row pills (4 per side × 2 sides = 8 W/L letters total).
      // We only assert the W-pill class shows up; pill letters duplicate
      // with the team-name strings so use a permissive finder.
      expect(find.text('W'), findsWidgets);
    },
  );

  testWidgets(
    'h2h section shows empty state when no entries are available',
    (tester) async {
      await _pump(tester, detail: _detail());

      expect(find.text('DIREKTER VERGLEICH'), findsOneWidget);
      expect(find.text('Noch keine direkten Vergleiche'), findsOneWidget);
    },
  );

  testWidgets(
    'match-setup section lists format / heli / penalty / court rows',
    (tester) async {
      await _pump(tester, detail: _detail());

      expect(find.text('MATCH-SETUP'), findsOneWidget);
      expect(find.text('Format'), findsOneWidget);
      expect(find.text('Heli-Tracking'), findsOneWidget);
      expect(find.text('Strafkubb'), findsOneWidget);
      expect(find.text('Court'), findsOneWidget);
      // Default values: heli=false → 'nein', penalty defaults to
      // 'schwedisch', format derived from BO3 fixture.
      expect(find.text('Best of 3 · 6 Stöcke'), findsOneWidget);
      expect(find.text('nein'), findsOneWidget);
      expect(find.text('schwedisch'), findsOneWidget);
    },
  );

  testWidgets(
    'creator with pending invites sees the ghost cancel button',
    (tester) async {
      await _pump(tester, detail: _detail());

      final cancel = find.widgetWithText(KubbButton, 'Match abbrechen');
      expect(cancel, findsOneWidget);
      final btn = tester.widget<KubbButton>(cancel);
      expect(btn.variant, KubbButtonVariant.ghost);
    },
  );

  testWidgets(
    'invitee with pending status sees the primary Bereit button',
    (tester) async {
      final started = DateTime.utc(2026, 5, 24, 10);
      final detail = _detail(
        participants: [
          MatchParticipant(
            participantId: 'p-1',
            teamId: 'A',
            kind: MatchParticipantKind.inApp,
            userId: 'user-creator',
            nickname: 'Marc',
            invitationStatus: MatchInvitationStatus.accepted,
            joinedAt: started,
            respondedAt: started,
          ),
          MatchParticipant(
            participantId: 'p-2',
            teamId: 'B',
            kind: MatchParticipantKind.inApp,
            userId: 'user-me',
            nickname: 'Vinz',
            invitationStatus: MatchInvitationStatus.pending,
            joinedAt: started,
            respondedAt: null,
          ),
        ],
      );
      await _pump(tester, detail: detail, currentUserId: 'user-me');

      final ready = find.widgetWithText(KubbButton, 'Bereit');
      expect(ready, findsOneWidget);
      final btn = tester.widget<KubbButton>(ready);
      expect(btn.variant, KubbButtonVariant.primary);

      // Non-creator → no cancel button.
      expect(find.widgetWithText(KubbButton, 'Match abbrechen'), findsNothing);
    },
  );
}
