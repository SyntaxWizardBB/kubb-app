import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/stats/application/match_stats_provider.dart';
import 'package:kubb_app/features/stats/data/match_stats_aggregate.dart';
import 'package:kubb_app/features/stats/presentation/widgets/match_stats_tab.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required MatchStatsAggregate aggregate,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchStatsProvider.overrideWith((ref) async => aggregate),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const Scaffold(body: MatchStatsTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows empty state when aggregate is empty', (tester) async {
    await pump(tester, aggregate: MatchStatsAggregate.empty);

    expect(find.text('Noch keine Matches'), findsOneWidget);
    expect(
      find.text(
        'Spiele dein erstes Match — die Statistik füllt sich automatisch.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders win count and recent-match row when populated',
      (tester) async {
    final agg = MatchStatsAggregate(
      totalMatches: 3,
      wins: 2,
      losses: 1,
      ties: 0,
      recentMatches: [
        MatchSummary(
          matchId: 'm-1',
          format: MatchFormat.bo3,
          scoring: MatchScoring.wins,
          status: MatchStatus.finalized,
          startedAt: DateTime.utc(2026, 5, 20, 10),
          completedAt: DateTime.utc(2026, 5, 20, 11),
          myTeamId: 'A',
          opponentTeamSize: 1,
          myRole: MatchRole.participant,
          winnerTeamId: 'A',
          finalScoreA: 2,
          finalScoreB: 1,
        ),
      ],
    );

    await pump(tester, aggregate: agg);

    // Wins value rendered.
    expect(find.text('2'), findsWidgets);
    // Recent matches section title.
    expect(find.text('Letzte Matches'.toUpperCase()), findsOneWidget);
    // Outcome chip.
    expect(find.text('Gewonnen'), findsOneWidget);
    // Score readout.
    expect(find.text('2:1'), findsOneWidget);
  });
}
