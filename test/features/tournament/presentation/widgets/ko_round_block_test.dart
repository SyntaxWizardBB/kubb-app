import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/ko_round_block.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

Future<MatchFormatSpec> _pump(
  WidgetTester tester, {
  required MatchFormatSpec spec,
}) async {
  late MatchFormatSpec last;
  last = spec;
  await tester.pumpWidget(
    MaterialApp(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('de'),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: KoRoundBlock(
              title: 'Final',
              spec: last,
              onChanged: (s) => setState(() => last = s),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return last;
}

void main() {
  testWidgets('shows no separate tiebreak-after time field', (tester) async {
    await _pump(
      tester,
      spec: const MatchFormatSpec(
        setsToWin: 2,
        maxSets: 3,
        timeLimitSeconds: 1800,
      ),
    );

    // The on/off switch is the only tiebreak control; the old "Tiebreak nach"
    // minute field is gone.
    expect(find.text('Tiebreak'), findsOneWidget);
    expect(find.textContaining('Tiebreak nach'), findsNothing);
  });

  testWidgets('toggling the switch only flips tiebreakEnabled, the trigger '
      'stays bound to the match time', (tester) async {
    await _pump(
      tester,
      spec: const MatchFormatSpec(
        setsToWin: 2,
        maxSets: 3,
        timeLimitSeconds: 1800,
        tiebreakEnabled: false,
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // No after-time field appears once enabled — the trigger is the match end.
    expect(find.textContaining('Tiebreak nach'), findsNothing);
  });

  test('an enabled spec triggers the tiebreak at the match end', () {
    const spec = MatchFormatSpec(
      setsToWin: 2,
      maxSets: 3,
      timeLimitSeconds: 1800,
    );
    expect(spec.tiebreakEnabled, isTrue);
    expect(spec.tiebreakAfterSeconds, 1800);

    expect(spec.copyWith(tiebreakEnabled: false).tiebreakAfterSeconds, isNull);
  });
}
