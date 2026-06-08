import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_skeleton.dart';
import 'package:kubb_app/features/tournament/data/elo_leaderboard_repository.dart';
import 'package:kubb_app/features/tournament/presentation/elo_leaderboard_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

EloLeaderboardRow _row({
  required int rank,
  required String nickname,
  required int elo,
  required int games,
  bool provisional = false,
}) =>
    EloLeaderboardRow(
      rank: rank,
      userId: 'u-$rank-$nickname',
      nickname: nickname,
      elo: elo,
      games: games,
      provisional: provisional,
    );

/// The app shell hosting the screen. Tests wrap this in their own
/// `ProviderScope` so each can stage data / loading overrides inline.
Widget get _shell => MaterialApp(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const EloLeaderboardScreen(),
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<EloLeaderboardRow> rows,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eloLeaderboardProvider.overrideWith((_) async => rows),
      ],
      child: _shell,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders top rows (nickname, elo, games) from the override',
      (tester) async {
    await _pump(tester, rows: [
      _row(rank: 1, nickname: 'Krähe', elo: 1620, games: 24),
      _row(rank: 2, nickname: 'Fuchs', elo: 1480, games: 12),
    ]);

    expect(find.text('Krähe'), findsOneWidget);
    expect(find.text('1620'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('Fuchs'), findsOneWidget);
    expect(find.text('1480'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('shows the provisional badge only on the provisional row',
      (tester) async {
    await _pump(tester, rows: [
      _row(rank: 1, nickname: 'Profi', elo: 1700, games: 40),
      _row(rank: 2, nickname: 'Neuling', elo: 1300, games: 4, provisional: true),
    ]);

    // Both rows render — provisional ones are marked, never hidden (§7).
    expect(find.text('Profi'), findsOneWidget);
    expect(find.text('Neuling'), findsOneWidget);
    // Badge appears exactly once, for the provisional row.
    expect(find.text('provisorisch'), findsOneWidget);
  });

  testWidgets('shows the German empty state for an empty list',
      (tester) async {
    await _pump(tester, rows: const <EloLeaderboardRow>[]);

    expect(find.text('Noch keine Wertungen'), findsOneWidget);
  });

  testWidgets('shows skeleton rows while loading', (tester) async {
    // Never-completing future keeps the provider in its loading state.
    final blocked = Completer<List<EloLeaderboardRow>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eloLeaderboardProvider.overrideWith((_) => blocked.future),
        ],
        child: _shell,
      ),
    );
    // Single frame only — pumpAndSettle would hang on the open future.
    await tester.pump();

    expect(find.byType(KubbSkeleton), findsWidgets);
    expect(find.text('Noch keine Wertungen'), findsNothing);

    blocked.complete(const <EloLeaderboardRow>[]);
  });

  testWidgets('shows the German error text when the provider throws',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eloLeaderboardProvider.overrideWith((_) async => throw Exception('x')),
        ],
        child: _shell,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Bestenliste konnte nicht geladen werden'),
      findsOneWidget,
    );
  });
}
