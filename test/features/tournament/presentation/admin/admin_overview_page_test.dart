import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/admin/admin_overview_blocks.dart';
import 'package:kubb_app/features/tournament/presentation/admin/admin_overview_page.dart';
import 'package:kubb_app/features/tournament/presentation/admin/live_round_panel.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  const data = AdminOverviewData(
    eyebrow: 'Turnierleitung · Live',
    title: 'Kommandozentrale',
    subtitle: 'Eine Liga läuft gerade.',
    tournamentLabel: 'BKC Friday League · KW 21',
    round: 3,
    roundTotal: 4,
    courts: [
      LiveCourt(
        name: 'Court 1',
        home: 'Wood Hammers',
        away: 'Bern Bombers',
        score: '3 : 0',
        done: true,
      ),
    ],
    timerDisplay: '12:34',
    timerRunning: true,
    roundLengthsMinutes: [15, 20, 25, 30],
    selectedRoundLengthMinutes: 20,
    stats: [
      AdminStat(label: 'Teams heute', value: '32', note: 'in 2 Turnieren'),
    ],
    tasks: [
      AdminTask(
        title: 'Score-Konflikt Court 3',
        meta: 'gemeldet 20:42',
        callToAction: 'Prüfen',
      ),
    ],
    standings: [
      AdminStandingsRow(
        rank: 1,
        team: 'Wood Hammers',
        record: '3-0',
        points: 9,
      ),
    ],
  );

  Future<void> pumpPage(WidgetTester tester, Size surface) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AdminOverviewPage(data: data)),
      ),
    );
  }

  testWidgets('shows header, live panel and all three lower blocks',
      (tester) async {
    await pumpPage(tester, const Size(1440, 1400));
    final l = await AppLocalizations.delegate.load(const Locale('de'));

    expect(find.text('Kommandozentrale'), findsOneWidget);
    expect(find.text('BKC Friday League · KW 21'), findsWidgets);
    expect(find.text('32'), findsOneWidget);
    expect(find.text(l.adminTasksTitle), findsOneWidget);
    expect(find.text('Wood Hammers'), findsWidgets);
  });

  testWidgets('takes the table after the round before the running one',
      (tester) async {
    await pumpPage(tester, const Size(1440, 1400));
    final l = await AppLocalizations.delegate.load(const Locale('de'));
    expect(
      find.text(l.adminStandingsEyebrow(2).toUpperCase()),
      findsOneWidget,
      reason: 'round 3 is running, so the table stands after round 2',
    );
  });

  testWidgets('puts queue and table side by side on a wide window',
      (tester) async {
    await pumpPage(tester, const Size(1440, 1400));
    final tasks = tester.getTopLeft(find.byType(AdminTasksCard));
    final standings = tester.getTopLeft(find.byType(AdminStandingsCard));
    expect(standings.dx, greaterThan(tasks.dx));
    expect(standings.dy, tasks.dy);
  });

  testWidgets('stacks them below the expanded width, queue first',
      (tester) async {
    await pumpPage(tester, const Size(900, 2200));
    final tasks = tester.getTopLeft(find.byType(AdminTasksCard));
    final standings = tester.getTopLeft(find.byType(AdminStandingsCard));
    expect(standings.dy, greaterThan(tasks.dy));
    expect(standings.dx, tasks.dx);
  });
}
