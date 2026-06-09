// ADR-0031 Phase C (Block C4 / OD-1): a tournamentSchedule inbox row renders
// the per-event German badge label (derived from action_payload['kind']) and,
// when the caller has a live active match, a "Zum Match" CTA whose pitch and
// opponent come from myActiveMatchProvider (CDC-backed) — never from the
// PII-free notify payload.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/inbox/application/inbox_controller.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';
import 'package:kubb_app/features/inbox/presentation/inbox_screen.dart';
import 'package:kubb_app/features/tournament/application/my_active_match_provider.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _tid = TournamentId('t-1');

InboxMessage _scheduleMessage(String tag) => InboxMessage(
      id: 'sched-$tag',
      kind: InboxMessageKind.tournamentSchedule,
      subject: 'Turnier-Ablauf',
      body: 'Deine nächste Runde ist veröffentlicht. — Pitch 3',
      sentAt: DateTime.utc(2026, 6, 9, 10),
      // Already read so opening the detail sheet does not hit markRead (which
      // would touch the un-initialised Supabase client in a widget test).
      readAt: DateTime.utc(2026, 6, 9, 10, 1),
      // PII-free payload: only tournament_id, round_number, phase,
      // pitch_number, kind — no opponent / user names.
      actionPayload: {
        'tournament_id': 't-1',
        'round_number': 2,
        'phase': 'pool',
        'pitch_number': 3,
        'kind': tag,
      },
    );

MyActiveMatch _activeMatch() => const MyActiveMatch(
      match: TournamentMatchRef(
        matchId: TournamentMatchId('m-7'),
        tournamentId: _tid,
        roundNumber: 1,
        matchNumberInRound: 7,
        participantA: TournamentParticipantId('me-1'),
        participantB: TournamentParticipantId('foe-1'),
        status: TournamentMatchStatus.scheduled,
        consensusRound: 1,
        participantADisplayName: 'Ich',
        participantBDisplayName: 'Gegner-Team',
      ),
      pitchLabel: '7',
      opponentName: 'Gegner-Team',
    );

Future<void> _pump(
  WidgetTester tester,
  List<InboxMessage> messages, {
  MyActiveMatch? activeMatch,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inboxMessagesProvider.overrideWith(
          (ref) => Stream<List<InboxMessage>>.value(messages),
        ),
        myActiveMatchProvider(_tid).overrideWith(
          (ref) => AsyncValue<MyActiveMatch?>.data(activeMatch),
        ),
      ],
      child: MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: const InboxScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // OD-1: one collective kind, six events — each payload tag drives its own
  // German badge label.
  const labels = <String, String>{
    'round_published': 'Neue Runde',
    'match_running': 'Match läuft',
    'paused': 'Turnier pausiert',
    'resumed': 'Turnier läuft weiter',
    'awaiting_results': 'Resultat fehlt',
    'tiebreak_hold': 'Tiebreak',
  };
  for (final entry in labels.entries) {
    testWidgets('tag ${entry.key} -> German badge "${entry.value}"',
        (tester) async {
      await _pump(tester, [_scheduleMessage(entry.key)]);
      expect(find.text(entry.value), findsWidgets);
    });
  }

  testWidgets('detail sheet shows the "Zum Match" CTA for an active match',
      (tester) async {
    await _pump(
      tester,
      [_scheduleMessage('match_running')],
      activeMatch: _activeMatch(),
    );

    await tester.tap(find.text('Match läuft').first);
    await tester.pumpAndSettle();

    expect(find.text('Zum Match'), findsOneWidget);
    // It is not a request: no accept/decline panel.
    expect(find.text('Annehmen'), findsNothing);
    expect(find.text('Ablehnen'), findsNothing);
  });

  testWidgets('no "Zum Match" CTA when the caller has no active match',
      (tester) async {
    await _pump(
      tester,
      [_scheduleMessage('round_published')],
      // activeMatch null -> CTA hidden, schedule stays informational.
    );

    await tester.tap(find.text('Neue Runde').first);
    await tester.pumpAndSettle();

    expect(find.text('Zum Match'), findsNothing);
  });
}
