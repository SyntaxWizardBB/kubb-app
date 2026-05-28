import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_forfeit_sheet.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _matchId = TournamentMatchId('m-1');

class _FakeRemote implements TournamentRemote {
  ({TournamentMatchId matchId, ForfeitAbsentSide side, String reason})? lastCall;
  Exception? throwOnNext;

  @override
  Future<void> declareForfeit({
    required TournamentMatchId matchId,
    required ForfeitAbsentSide absentSide,
    required String reason,
  }) async {
    final err = throwOnNext;
    if (err != null) throw err;
    lastCall = (matchId: matchId, side: absentSide, reason: reason);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<_FakeRemote> _pumpSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final remote = _FakeRemote();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(remote),
      ],
      child: MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => TournamentForfeitSheet.show(
                  ctx,
                  matchId: _matchId,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return remote;
}

void main() {
  testWidgets('renders title, both side radios and reason field',
      (tester) async {
    await _pumpSheet(tester);
    expect(find.text('Forfeit erklären'), findsWidgets);
    expect(find.text('Team A'), findsOneWidget);
    expect(find.text('Team B'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Forfeit speichern'), findsOneWidget);
  });

  testWidgets(
      'submit without side or reason surfaces validation and does not call RPC',
      (tester) async {
    final remote = await _pumpSheet(tester);
    await tester.tap(find.text('Forfeit speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Bitte abwesende Seite auswählen.'), findsOneWidget);
    expect(find.text('Begründung muss mindestens 10 Zeichen enthalten.'),
        findsOneWidget);
    expect(remote.lastCall, isNull);
  });

  testWidgets(
      'reason shorter than 10 chars keeps the submit blocked even after side pick',
      (tester) async {
    final remote = await _pumpSheet(tester);
    await tester.tap(find.text('Team A'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'kurz');
    await tester.pump();
    await tester.tap(find.text('Forfeit speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Begründung muss mindestens 10 Zeichen enthalten.'),
        findsOneWidget);
    expect(remote.lastCall, isNull);
  });

  testWidgets('valid input calls declareForfeit with the chosen side + reason',
      (tester) async {
    final remote = await _pumpSheet(tester);
    await tester.tap(find.text('Team B'));
    await tester.pump();
    await tester.enterText(
      find.byType(TextField),
      'Team B war nicht am Pitch nach 15 Minuten Wartezeit.',
    );
    await tester.pump();
    await tester.tap(find.text('Forfeit speichern'));
    await tester.pumpAndSettle();
    expect(remote.lastCall, isNotNull);
    expect(remote.lastCall!.matchId, _matchId);
    expect(remote.lastCall!.side, ForfeitAbsentSide.b);
    expect(remote.lastCall!.reason,
        'Team B war nicht am Pitch nach 15 Minuten Wartezeit.');
  });
}
