import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/bracket_canvas.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_bracket_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Bracket bracket,
  String id = 't-1',
}) async {
  final router = GoRouter(
    initialLocation: '/tournament/$id/bracket',
    routes: <GoRoute>[
      GoRoute(
        path: '/tournament/:id/bracket',
        builder: (_, s) => TournamentBracketScreen(
          tournamentId: s.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/tournament/:id',
        builder: (_, _) => const Scaffold(body: Text('detail')),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId',
        builder: (_, _) => const Scaffold(body: Text('match')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentBracketProvider(TournamentId(id))
            .overrideWith((_) async => bracket),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: KubbTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

BracketPairing _pair(String a, String b) => (
      (seed: 1, participantId: a, isBye: false),
      (seed: 2, participantId: b, isBye: false),
    );

void main() {
  testWidgets('renders empty-state when bracket has no rounds',
      (tester) async {
    await _pump(
      tester,
      bracket: const SingleEliminationBracket(rounds: <BracketRound>[]),
    );
    expect(find.text('KO noch nicht gestartet'), findsOneWidget);
    expect(find.byType(BracketCanvas), findsNothing);
  });

  testWidgets('renders BracketCanvas when bracket has rounds',
      (tester) async {
    final bracket = SingleEliminationBracket(
      rounds: <BracketRound>[
        BracketRound(
          number: 1,
          pairings: <BracketPairing>[_pair('alpha', 'beta')],
        ),
      ],
    );
    await _pump(tester, bracket: bracket);
    expect(find.byType(BracketCanvas), findsOneWidget);
    expect(find.text('KO noch nicht gestartet'), findsNothing);
  });

  testWidgets('AppBar title uses l10n key', (tester) async {
    await _pump(
      tester,
      bracket: const SingleEliminationBracket(rounds: <BracketRound>[]),
    );
    expect(find.text('KO-Bracket'), findsOneWidget);
  });
}
