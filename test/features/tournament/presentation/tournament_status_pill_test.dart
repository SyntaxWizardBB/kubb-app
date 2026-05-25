import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_status_pill.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

Future<void> _pump(WidgetTester tester, TournamentStatus s) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: TournamentStatusPill(status: s))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('draft pill shows Entwurf', (tester) async {
    await _pump(tester, TournamentStatus.draft);
    expect(find.text('Entwurf'), findsOneWidget);
  });

  testWidgets('registration-open pill uses meadow palette', (tester) async {
    await _pump(tester, TournamentStatus.registrationOpen);
    expect(find.text('Anmeldung offen'), findsOneWidget);
    final container = tester.widget<Container>(
      find.ancestor(
        of: find.text('Anmeldung offen'),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, KubbTokens.meadow100);
  });

  testWidgets('aborted pill shows Abgebrochen label', (tester) async {
    await _pump(tester, TournamentStatus.aborted);
    expect(find.text('Abgebrochen'), findsOneWidget);
  });

  testWidgets('live pill shows Läuft label', (tester) async {
    await _pump(tester, TournamentStatus.live);
    expect(find.text('Läuft'), findsOneWidget);
  });
}
