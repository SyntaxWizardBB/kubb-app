import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_chip.dart';
import 'package:kubb_app/features/player/data/player_elo_ratings.dart';
import 'package:kubb_app/features/player/presentation/player_elo_summary.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  Future<void> pump(WidgetTester tester, PlayerEloRatings ratings) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(KubbTokens.space4),
            child: PlayerEloSummary(ratings: ratings),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('(a) tournament only: personal block is not shown',
      (tester) async {
    await pump(
      tester,
      const PlayerEloRatings(
        tournament: TournamentElo(elo: 1320, games: 20),
      ),
    );

    expect(find.text('1320'), findsOneWidget);
    expect(find.text('Persönlich'), findsNothing);
    expect(find.byIcon(KubbIcons.lock), findsNothing);
  });

  testWidgets('(b) tournament + personal: both shown, personal labelled private',
      (tester) async {
    await pump(
      tester,
      const PlayerEloRatings(
        tournament: TournamentElo(elo: 1320, games: 20),
        personal: PersonalElo(elo: 1180, games: 6),
      ),
    );

    expect(find.text('1320'), findsOneWidget);
    expect(find.text('1180'), findsOneWidget);
    expect(find.text('Persönlich'), findsOneWidget);
    expect(find.byIcon(KubbIcons.lock), findsOneWidget);
  });

  testWidgets('(c) provisional badge shows for games < 10 and hides for >= 10',
      (tester) async {
    await pump(
      tester,
      const PlayerEloRatings(
        tournament: TournamentElo(elo: 1210, games: 4),
      ),
    );
    expect(find.byType(KubbChip), findsOneWidget);
    expect(find.text('provisorisch'), findsOneWidget);

    await pump(
      tester,
      const PlayerEloRatings(
        tournament: TournamentElo(elo: 1400, games: 30),
      ),
    );
    expect(find.byType(KubbChip), findsNothing);
    expect(find.text('provisorisch'), findsNothing);
  });

  testWidgets('(d) no tournament: hint shown, no crash, personal stays hidden',
      (tester) async {
    await pump(tester, const PlayerEloRatings());

    expect(find.text('noch keine Wertung'), findsOneWidget);
    expect(find.text('Persönlich'), findsNothing);
    expect(find.byIcon(KubbIcons.lock), findsNothing);
  });
}
