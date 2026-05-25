import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/tournament_conflict_provider.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/conflict_comparison_row.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

TournamentSetScoreProposal _proposal({
  required String submitter,
  required int setNumber,
  required int kA,
  required int kB,
  required SetWinner winner,
}) {
  return TournamentSetScoreProposal(
    matchId: const TournamentMatchId('m-1'),
    consensusRound: 2,
    setNumber: setNumber,
    submitterUserId: UserId(submitter),
    score: SetScore(
      basekubbsKnockedByA: kA,
      basekubbsKnockedByB: kB,
      winner: winner,
    ),
  );
}

Future<void> _pump(WidgetTester tester, TournamentSetProposalPair pair) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: KubbTheme.light(),
      home: Scaffold(body: ConflictComparisonRow(pair: pair)),
    ),
  );
  await tester.pumpAndSettle();
}

bool _hasDiffBackground(WidgetTester tester) {
  final containers = tester.widgetList<Container>(find.byType(Container));
  for (final c in containers) {
    final d = c.decoration;
    if (d is BoxDecoration && d.color == KubbTokens.miss) return true;
  }
  return false;
}

void main() {
  testWidgets('matching proposals render without diff highlight',
      (tester) async {
    final pair = TournamentSetProposalPair(
      setNumber: 1,
      teamA: _proposal(
          submitter: 'a', setNumber: 1, kA: 5, kB: 3, winner: SetWinner.teamA),
      teamB: _proposal(
          submitter: 'b', setNumber: 1, kA: 5, kB: 3, winner: SetWinner.teamA),
    );
    await _pump(tester, pair);
    expect(find.text('Satz 1'), findsOneWidget);
    expect(_hasDiffBackground(tester), isFalse);
  });

  testWidgets('diverging proposals highlight diff cells', (tester) async {
    final pair = TournamentSetProposalPair(
      setNumber: 2,
      teamA: _proposal(
          submitter: 'a', setNumber: 2, kA: 5, kB: 2, winner: SetWinner.teamA),
      teamB: _proposal(
          submitter: 'b', setNumber: 2, kA: 4, kB: 5, winner: SetWinner.teamB),
    );
    await _pump(tester, pair);
    expect(find.text('Satz 2'), findsOneWidget);
    expect(_hasDiffBackground(tester), isTrue);
  });
}
