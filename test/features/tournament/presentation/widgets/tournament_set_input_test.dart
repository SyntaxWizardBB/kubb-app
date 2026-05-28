import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_set_input.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

Future<void> _pump(
  WidgetTester tester, {
  required int basekubbsA,
  required int basekubbsB,
  required SetWinner? king,
  required ValueChanged<TournamentSetInputValue> onChanged,
  int max = 5,
  bool enabled = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: KubbTheme.light(),
      home: Scaffold(
        body: TournamentSetInput(
          setNumber: 1,
          basekubbsA: basekubbsA,
          basekubbsB: basekubbsB,
          king: king,
          maxBasekubbs: max,
          enabled: enabled,
          onChanged: onChanged,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('plus button increments team A basekubbs up to max',
      (tester) async {
    var captured = const TournamentSetInputValue(
      basekubbsA: 4,
      basekubbsB: 0,
      king: null,
    );
    await _pump(
      tester,
      basekubbsA: 4,
      basekubbsB: 0,
      king: null,
      onChanged: (v) => captured = v,
    );
    final plus = find.byIcon(LucideIcons.plus).first;
    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(captured.basekubbsA, 5);
  });

  testWidgets('plus is disabled at max basekubbs', (tester) async {
    var captured = const TournamentSetInputValue(
      basekubbsA: 5,
      basekubbsB: 0,
      king: null,
    );
    await _pump(
      tester,
      basekubbsA: 5,
      basekubbsB: 0,
      king: null,
      onChanged: (v) => captured = v,
    );
    final plus = find.byIcon(LucideIcons.plus).first;
    await tester.tap(plus);
    await tester.pumpAndSettle();
    // No change emitted — button onPressed was null.
    expect(captured.basekubbsA, 5);
  });

  testWidgets('king toggle reports the chosen winner', (tester) async {
    TournamentSetInputValue? captured;
    await _pump(
      tester,
      basekubbsA: 5,
      basekubbsB: 0,
      king: null,
      onChanged: (v) => captured = v,
    );
    await tester.tap(find.text('Team A'));
    await tester.pumpAndSettle();
    expect(captured, isNotNull);
    expect(captured!.king, SetWinner.teamA);
  });

  // Sprint A W3-T2 / R11-F-01: the per-set king-outcome is exposed as a
  // tri-toggle. The three branches below exercise each position so the
  // mapping from button label to the emitted [SetWinner?] value stays
  // pinned. The "Keiner" branch is the new path that lets the parent
  // screen lift the choice into a [KingTimedOut] outcome and route it
  // through the EKC pipeline as a 0:0-contribution set.
  testWidgets('tri-toggle: tapping Team A emits SetWinner.teamA',
      (tester) async {
    TournamentSetInputValue? captured;
    await _pump(
      tester,
      basekubbsA: 5,
      basekubbsB: 3,
      king: null,
      onChanged: (v) => captured = v,
    );
    await tester.tap(find.text('Team A'));
    await tester.pumpAndSettle();
    expect(captured?.king, SetWinner.teamA);
  });

  testWidgets('tri-toggle: tapping Team B emits SetWinner.teamB',
      (tester) async {
    TournamentSetInputValue? captured;
    await _pump(
      tester,
      basekubbsA: 3,
      basekubbsB: 5,
      king: SetWinner.teamA,
      onChanged: (v) => captured = v,
    );
    await tester.tap(find.text('Team B'));
    await tester.pumpAndSettle();
    expect(captured?.king, SetWinner.teamB);
  });

  testWidgets('tri-toggle: tapping Keiner emits null (timed-out path)',
      (tester) async {
    TournamentSetInputValue? captured;
    await _pump(
      tester,
      basekubbsA: 5,
      basekubbsB: 0,
      king: SetWinner.teamA,
      onChanged: (v) => captured = v,
    );
    await tester.tap(find.text('Keiner'));
    await tester.pumpAndSettle();
    expect(captured, isNotNull,
        reason: 'tapping the third toggle position must emit a value');
    expect(captured!.king, isNull,
        reason: 'the "Keiner" option encodes a timed-out set '
            '(parent screen maps null to KingTimedOut)');
    expect(captured!.basekubbsA, 5);
    expect(captured!.basekubbsB, 0);
  });
}
