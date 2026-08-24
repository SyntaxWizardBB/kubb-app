import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/admin/admin_overview_blocks.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size surface = const Size(1100, 900),
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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  group('AdminStatsRow', () {
    const stats = [
      AdminStat(label: 'Teams heute', value: '32', note: 'in 2 Turnieren'),
      AdminStat(label: 'Matches offen', value: '11', note: 'Runde 3'),
      AdminStat(label: 'Konflikte', value: '2', note: 'warten auf dich'),
      AdminStat(label: 'Gebühren offen', value: 'CHF 150', note: '6 Teams'),
    ];

    testWidgets('renders every tile with its label, value and note',
        (tester) async {
      await pump(tester, const AdminStatsRow(stats: stats));
      expect(find.text('32'), findsOneWidget);
      expect(find.text('CHF 150'), findsOneWidget);
      expect(find.text('TEAMS HEUTE'), findsOneWidget);
      expect(find.text('warten auf dich'), findsOneWidget);
    });

    testWidgets('still renders every tile when the window is phone-narrow',
        (tester) async {
      await pump(
        tester,
        const AdminStatsRow(stats: stats),
        surface: const Size(380, 1400),
      );
      for (final stat in stats) {
        expect(find.text(stat.value), findsOneWidget);
      }
    });
  });

  group('AdminTasksCard', () {
    const tasks = [
      AdminTask(
        title: 'Score-Konflikt Court 3',
        meta: 'Bern Bombers vs. Pia & Tobi',
        callToAction: 'Prüfen',
        urgency: AdminTaskUrgency.critical,
      ),
      AdminTask(
        title: 'Anmeldung offen',
        meta: 'Emmental Eichen',
        callToAction: 'Aufnehmen',
      ),
    ];

    testWidgets('counts the open tasks in its header', (tester) async {
      await pump(tester, const AdminTasksCard(tasks: tasks));
      final l = await AppLocalizations.delegate.load(const Locale('de'));
      expect(find.text(l.adminTasksOpenCount(2)), findsOneWidget);
    });

    testWidgets('hands the tapped task back rather than just firing',
        (tester) async {
      AdminTask? acted;
      await pump(
        tester,
        AdminTasksCard(tasks: tasks, onTaskAction: (t) => acted = t),
      );
      await tester.tap(find.text('Aufnehmen'));
      await tester.pump();
      expect(acted?.title, 'Anmeldung offen');
    });

    testWidgets('an empty queue renders the header and no rows',
        (tester) async {
      await pump(tester, const AdminTasksCard(tasks: []));
      final l = await AppLocalizations.delegate.load(const Locale('de'));
      expect(find.text(l.adminTasksTitle), findsOneWidget);
      expect(find.text(l.adminTasksOpenCount(0)), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('AdminStandingsCard', () {
    const rows = [
      AdminStandingsRow(rank: 1, team: 'Wood Hammers', record: '3-0', points: 9),
      AdminStandingsRow(rank: 2, team: 'BKC United A', record: '2-1', points: 7),
      AdminStandingsRow(rank: 4, team: 'Bern Bombers', record: '1-2', points: 5),
    ];

    testWidgets('names the round the table was taken after', (tester) async {
      await pump(
        tester,
        const AdminStandingsCard(
          tournamentLabel: 'BKC Friday League',
          afterRound: 2,
          rows: rows,
        ),
      );
      final l = await AppLocalizations.delegate.load(const Locale('de'));
      expect(
        find.text(l.adminStandingsEyebrow(2).toUpperCase()),
        findsOneWidget,
      );
      expect(find.text('BKC Friday League'), findsOneWidget);
    });

    testWidgets('shows rank, record and points for every row', (tester) async {
      await pump(
        tester,
        const AdminStandingsCard(
          tournamentLabel: 'BKC Friday League',
          afterRound: 2,
          rows: rows,
        ),
      );
      expect(find.text('Wood Hammers'), findsOneWidget);
      expect(find.text('3-0'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });
  });
}
