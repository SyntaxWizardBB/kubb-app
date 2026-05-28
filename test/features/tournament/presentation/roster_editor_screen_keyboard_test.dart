// Widget regression for Mängel #2.4 (BH-C-03, W4.1-E):
// The mid-tournament roster editor must respect the IME's `viewInsets`
// so the "Ersetzen" action row and audit-trail stay reachable when the
// replacement dialog opens a soft keyboard. We fake a 320px keyboard
// insert and assert (a) `resizeToAvoidBottomInset` is on, (b) the
// ListView padding includes the IME bottom inset.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/presentation/roster_editor_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

Future<void> _pumpWithInsets(
  WidgetTester tester, {
  required double bottomInset,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final slots = <RosterSlot>[
    RosterSlot(
      id: 'slot-1',
      slotIndex: 1,
      memberUserId: const UserId('u1'),
      guestPlayerId: null,
      assignedAt: DateTime.utc(2026),
      assignedBy: const UserId('u-org'),
    ),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rosterProvider(const TournamentParticipantId('p-1'))
            .overrideWith((_) async => slots),
        tournamentDetailProvider(const TournamentId('t-1'))
            .overrideWith((_) async => null),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          viewInsets: EdgeInsets.only(bottom: bottomInset),
        ),
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const RosterEditorScreen(
            tournamentId: TournamentId('t-1'),
            participantId: TournamentParticipantId('p-1'),
            teamId: TeamId('team-1'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Mängel #2.4: roster editor ListView padding tracks 320px keyboard insert',
    (tester) async {
      await _pumpWithInsets(tester, bottomInset: 320);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.resizeToAvoidBottomInset, isTrue);

      final listFinder = find.byType(ListView);
      expect(listFinder, findsOneWidget);

      final list = tester.widget<ListView>(listFinder);
      expect(
        list.padding!.resolve(TextDirection.ltr).bottom,
        greaterThanOrEqualTo(320),
        reason: 'roster ListView padding must absorb the keyboard insert',
      );
    },
  );
}
