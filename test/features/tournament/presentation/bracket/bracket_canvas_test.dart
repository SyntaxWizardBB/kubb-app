import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/bracket_canvas.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/kubb_match_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _id = TournamentId('t-1');
final _bracket = Bracket.singleElimination(
  const ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'],
);

class _Handle {
  String? lastPushed;
}

Future<_Handle> _pump(WidgetTester tester, {bool editable = true}) async {
  final h = _Handle();
  final router = GoRouter(
    initialLocation: '/tournament/t-1/bracket',
    routes: [
      GoRoute(
        path: '/tournament/:id/bracket',
        builder: (_, _) => Scaffold(
          body: BracketCanvas(
            bracket: _bracket,
            editable: editable,
            tournamentId: _id,
          ),
        ),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId',
        builder: (_, s) {
          h.lastPushed =
              '/tournament/${s.pathParameters['id']}/match/${s.pathParameters['matchId']}';
          return const Scaffold(body: Text('match-route'));
        },
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp.router(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return h;
}

void main() {
  testWidgets('8-team bracket renders 7 KubbMatchCard widgets', (tester) async {
    await _pump(tester);
    expect(find.byType(KubbMatchCard), findsNWidgets(7));
  });

  testWidgets('tap on match card navigates to /<id>/match/<matchId>',
      (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.byType(KubbMatchCard).first);
    await tester.pumpAndSettle();
    expect(h.lastPushed, startsWith('/tournament/t-1/match/'));
  });

  testWidgets('read-only mode does not open override dialog on tap',
      (tester) async {
    await _pump(tester, editable: false);
    await tester.tap(find.byType(KubbMatchCard).first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
