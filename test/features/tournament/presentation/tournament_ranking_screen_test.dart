import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/data/tournament_ranking_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_ranking_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

TournamentRankingRow _row({
  required String name,
  required double points,
  required int count,
  required int rank,
}) =>
    TournamentRankingRow(
      participantId: 'p-$rank-$name',
      displayName: name,
      totalPoints: points,
      tournamentCount: count,
      rank: rank,
    );

/// The app shell hosting the screen. Tests wrap this in their own
/// `ProviderScope` so each can stage data / loading / error overrides
/// inline (avoids naming riverpod's non-exported `Override` type).
Widget get _shell => MaterialApp(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const TournamentRankingScreen(),
    );

Future<void> _pump(
  WidgetTester tester, {
  required Map<RankingBucket, List<TournamentRankingRow>> data,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        for (final entry in data.entries)
          tournamentRankingProvider(entry.key)
              .overrideWith((_) async => entry.value),
      ],
      child: _shell,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders four league/single tabs', (tester) async {
    await _pump(tester, data: const {});

    expect(find.text('Liga A'), findsOneWidget);
    expect(find.text('Liga B'), findsOneWidget);
    expect(find.text('Liga C'), findsOneWidget);
    expect(find.text('Einzel'), findsOneWidget);
  });

  testWidgets('renders ranking rows from the override', (tester) async {
    await _pump(tester, data: {
      RankingBucket.ligaA: [
        _row(name: 'Team Krähe', points: 12.5, count: 3, rank: 1),
        _row(name: 'Team Fuchs', points: 9, count: 2, rank: 2),
      ],
    });

    // Rank, name, points (1 decimal) and tournament count all surface.
    expect(find.text('Team Krähe'), findsOneWidget);
    expect(find.text('12.5'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('Team Fuchs'), findsOneWidget);
    expect(find.text('9.0'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('switching to another tab shows that bucket rows',
      (tester) async {
    await _pump(tester, data: {
      RankingBucket.ligaA: [
        _row(name: 'Liga-A-Team', points: 5, count: 1, rank: 1),
      ],
      RankingBucket.einzel: [
        _row(name: 'Solo-Spieler', points: 8, count: 4, rank: 1),
      ],
    });

    expect(find.text('Liga-A-Team'), findsOneWidget);
    expect(find.text('Solo-Spieler'), findsNothing);

    await tester.tap(find.text('Einzel'));
    await tester.pumpAndSettle();

    expect(find.text('Solo-Spieler'), findsOneWidget);
    expect(find.text('Liga-A-Team'), findsNothing);
  });

  testWidgets('shows the German empty state for an empty bucket',
      (tester) async {
    await _pump(tester, data: {
      RankingBucket.ligaA: const <TournamentRankingRow>[],
    });

    expect(find.text('Noch keine Wertungen'), findsOneWidget);
  });

  testWidgets('shows a spinner while the active bucket is loading',
      (tester) async {
    // Never-completing future keeps the provider in its loading state.
    final blocked = Completer<List<TournamentRankingRow>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tournamentRankingProvider(RankingBucket.ligaA)
              .overrideWith((_) => blocked.future),
        ],
        child: _shell,
      ),
    );
    // Single frame only — pumpAndSettle would hang on the open future.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Noch keine Wertungen'), findsNothing);

    blocked.complete(const <TournamentRankingRow>[]);
  });

  testWidgets('shows the German error text when the provider throws',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tournamentRankingProvider(RankingBucket.ligaA)
              .overrideWith((_) async => throw Exception('boom')),
        ],
        child: _shell,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Rangliste konnte nicht geladen werden'),
      findsOneWidget,
    );
  });
}
