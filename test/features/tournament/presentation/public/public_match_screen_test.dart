// Widget tests for TASK-M4.2-T13 (Public-Match-Screen).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/presentation/public/public_match_screen.dart';

Future<void> _pump(
  WidgetTester tester, {
  required PublicMatchView view,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        publicMatchViewProvider('m-1').overrideWith((_) => view),
      ],
      child: const MaterialApp(
        home: PublicMatchScreen(matchId: 'm-1'),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('Mock-Match → Sets-Stand sichtbar', (tester) async {
    await _pump(
      tester,
      view: const PublicMatchView(
        teamA: 'Team Alpha',
        teamB: 'Team Beta',
        setsWonA: 2,
        setsWonB: 1,
      ),
    );
    expect(find.byKey(const ValueKey('public-sets-stand')), findsOneWidget);
    expect(find.text('2 : 1'), findsOneWidget);
    expect(find.text('Team Alpha'), findsOneWidget);
    expect(find.text('Team Beta'), findsOneWidget);
  });

  testWidgets('Read-only: keine Eingabe-Widgets im Render-Tree',
      (tester) async {
    await _pump(
      tester,
      view: const PublicMatchView(
        teamA: 'Team Alpha',
        teamB: 'Team Beta',
        setsWonA: 0,
        setsWonB: 0,
      ),
    );
    expect(find.byType(TextField).evaluate().isEmpty, isTrue);
    expect(
      find.widgetWithText(FilledButton, 'Speichern').evaluate().isEmpty,
      isTrue,
    );
  });
}
