import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/widgets/match_stage_indicator.dart';

Future<void> _pump(WidgetTester tester, MatchStatus status) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: KubbTheme.light(),
      home: Scaffold(
        body: MatchStageIndicator(status: status),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Asserts the pill labelled [label] is the visually active one
/// (stone-900 background, chalk-50 text) and that the others fall back
/// to a transparent background.
void _expectActivePill(WidgetTester tester, String label) {
  // Active pill — exact label match, expect stone-900 background.
  final activeContainer = tester.widget<Container>(
    find
        .ancestor(
          of: find.text(label),
          matching: find.byType(Container),
        )
        .first,
  );
  final activeDecoration = activeContainer.decoration as BoxDecoration?;
  expect(
    activeDecoration?.color,
    KubbTokens.stone900,
    reason: '"$label" pill should be active (stone-900)',
  );

  // Active label color should be chalk-50.
  final activeText = tester.widget<Text>(find.text(label));
  expect(activeText.style?.color, KubbTokens.chalk50);
}

void _expectInactivePill(WidgetTester tester, String label) {
  final inactiveContainer = tester.widget<Container>(
    find
        .ancestor(
          of: find.text(label),
          matching: find.byType(Container),
        )
        .first,
  );
  final inactiveDecoration = inactiveContainer.decoration as BoxDecoration?;
  expect(
    inactiveDecoration?.color,
    Colors.transparent,
    reason: '"$label" pill should be inactive (transparent)',
  );
}

void main() {
  group('MatchStageIndicator — status → active-pill mapping', () {
    testWidgets('pendingInvites → Lobby active', (tester) async {
      await _pump(tester, MatchStatus.pendingInvites);
      _expectActivePill(tester, 'Lobby');
      _expectInactivePill(tester, 'Live');
      _expectInactivePill(tester, 'Ergebnis');
    });

    testWidgets('active → Live active', (tester) async {
      await _pump(tester, MatchStatus.active);
      _expectActivePill(tester, 'Live');
      _expectInactivePill(tester, 'Lobby');
      _expectInactivePill(tester, 'Ergebnis');
    });

    testWidgets('awaitingResults → Ergebnis active', (tester) async {
      await _pump(tester, MatchStatus.awaitingResults);
      _expectActivePill(tester, 'Ergebnis');
      _expectInactivePill(tester, 'Lobby');
      _expectInactivePill(tester, 'Live');
    });

    testWidgets('finalized → Ergebnis active', (tester) async {
      await _pump(tester, MatchStatus.finalized);
      _expectActivePill(tester, 'Ergebnis');
      _expectInactivePill(tester, 'Lobby');
      _expectInactivePill(tester, 'Live');
    });

    testWidgets('voided → Ergebnis active', (tester) async {
      await _pump(tester, MatchStatus.voided);
      _expectActivePill(tester, 'Ergebnis');
      _expectInactivePill(tester, 'Lobby');
      _expectInactivePill(tester, 'Live');
    });
  });

}
