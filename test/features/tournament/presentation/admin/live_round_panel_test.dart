import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/admin/live_round_panel.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  const courts = [
    LiveCourt(
      name: 'Court 1',
      home: 'Solothurn Slingers',
      away: 'Wood Hammers',
      score: '3 : 0',
      done: true,
    ),
    LiveCourt(
      name: 'Court 2',
      home: 'Marc & Vinz',
      away: 'BKC United A',
      score: '2 : 1',
      done: false,
    ),
    LiveCourt(
      name: 'Court 3',
      home: 'Bern Bombers',
      away: 'Pia & Tobi',
      score: '1 : 1',
      done: false,
    ),
    LiveCourt(
      name: 'Court 4',
      home: 'Zürichsee Casuals',
      away: 'BKC United B',
      score: '0 : 2',
      done: false,
    ),
  ];

  Future<void> pumpPanel(
    WidgetTester tester, {
    bool running = true,
    bool paused = false,
    void Function(int)? onNudge,
    VoidCallback? onToggle,
    void Function(LiveCourt)? onCourtDetails,
    Size surface = const Size(1440, 1200),
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: LiveRoundPanel(
              tournamentLabel: 'BKC Friday League · KW 21',
              round: 3,
              roundTotal: 4,
              courts: courts,
              timerDisplay: '12:34',
              timerRunning: running,
              paused: paused,
              roundLengthsMinutes: const [15, 20, 25, 30],
              selectedRoundLengthMinutes: 20,
              onTimerNudge: onNudge,
              onTimerToggle: onToggle,
              onCourtDetails: onCourtDetails,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('counts only the finished courts towards the round progress',
      (tester) async {
    await pumpPanel(tester);
    final l = await AppLocalizations.delegate.load(const Locale('de'));
    expect(find.text(l.adminCourtsDone(1, 4)), findsOneWidget);
    expect(find.text(l.adminRoundOf(3, 4)), findsNothing,
        reason: 'the label is rendered upper-cased');
    expect(find.text(l.adminRoundOf(3, 4).toUpperCase()), findsOneWidget);

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.25);
  });

  testWidgets('the clock toggle reads Pause while running and Start when not',
      (tester) async {
    final l = await AppLocalizations.delegate.load(const Locale('de'));

    await pumpPanel(tester);
    expect(find.text(l.adminTimerPause), findsOneWidget);
    expect(find.text(l.adminTimerStart), findsNothing);

    await pumpPanel(tester, running: false);
    expect(find.text(l.adminTimerStart), findsOneWidget);
  });

  testWidgets('the pause action flips its label once the round is paused',
      (tester) async {
    final l = await AppLocalizations.delegate.load(const Locale('de'));

    await pumpPanel(tester);
    expect(find.text(l.adminActionPauseRound), findsOneWidget);

    await pumpPanel(tester, paused: true);
    expect(find.text(l.adminActionResumeRound), findsOneWidget);
    expect(find.text(l.adminActionPauseRound), findsNothing);
  });

  testWidgets('nudging reports a signed minute, not just a tap',
      (tester) async {
    final nudges = <int>[];
    await pumpPanel(tester, onNudge: nudges.add);
    final l = await AppLocalizations.delegate.load(const Locale('de'));

    await tester.tap(find.text(l.adminTimerBack));
    await tester.tap(find.text(l.adminTimerForward));
    await tester.pump();

    expect(nudges, [-1, 1]);
  });

  testWidgets('hands the tapped court back to the caller', (tester) async {
    LiveCourt? opened;
    await pumpPanel(tester, onCourtDetails: (c) => opened = c);
    final l = await AppLocalizations.delegate.load(const Locale('de'));

    await tester.tap(find.text(l.adminCourtDetails).at(2));
    await tester.pump();

    expect(opened?.name, 'Court 3');
  });

  testWidgets('reflows the court grid to one column on a narrow window',
      (tester) async {
    await pumpPanel(tester, surface: const Size(420, 1600));
    final cards = tester.widgetList<SizedBox>(
      find.ancestor(
        of: find.text('COURT 1'),
        matching: find.byType(SizedBox),
      ),
    );
    expect(cards, isNotEmpty);
    expect(find.text('COURT 4'), findsOneWidget,
        reason: 'every court still renders, just stacked');
  });
}
