// N1/C3: the tournament-finished inbox message renders cleanly in the
// Postfach — a German "Turnier beendet" badge label and the body text
// (including the configured round time the server put there) are shown.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/inbox/application/inbox_controller.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';
import 'package:kubb_app/features/inbox/presentation/inbox_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

InboxMessage _finishedMessage() => InboxMessage(
      id: 'fin-1',
      kind: InboxMessageKind.tournamentFinished,
      subject: 'Turnier beendet',
      body: 'Turnier "ProbeCup" ist beendet. Danke fürs Mitspielen! '
          '— Spielzeit 30 min',
      sentAt: DateTime.utc(2026, 6, 6, 10),
      actionPayload: const {'tournament_id': 't-1', 'phase': 'finished'},
    );

Future<void> _pump(WidgetTester tester, List<InboxMessage> messages) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inboxMessagesProvider.overrideWith(
          (ref) => Stream<List<InboxMessage>>.value(messages),
        ),
      ],
      child: MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: const InboxScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tournament-finished renders the German label and round-time body',
      (tester) async {
    await _pump(tester, [_finishedMessage()]);

    // German badge label for the new kind.
    expect(find.text('Turnier beendet'), findsWidgets);
    // The configured round time arrives as part of the body — no special
    // client logic, it is just shown.
    expect(
      find.textContaining('Spielzeit 30 min'),
      findsOneWidget,
    );
    // It is a plain informational message: no accept/decline action panel.
    expect(find.text('Annehmen'), findsNothing);
    expect(find.text('Ablehnen'), findsNothing);
  });
}
