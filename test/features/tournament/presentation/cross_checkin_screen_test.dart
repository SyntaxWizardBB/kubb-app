import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/cross_checkin_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Spy [TournamentRemote] for the cross-checkin screen (W4-T22). Returns canned
/// [CheckinSearchHit]s filtered by a case-insensitive substring and records the
/// participant ids passed to [checkinParticipant] so the test can assert the
/// toggle dispatched the check-in. Every other method throws via [noSuchMethod]
/// — the screen only reaches the search + check-in path.
class _SpyRemote implements TournamentRemote {
  _SpyRemote(this.hits);

  final List<CheckinSearchHit> hits;
  final List<String> checkins = <String>[];

  @override
  Future<List<CheckinSearchHit>> searchCheckinTargets(String query) async {
    final needle = query.toLowerCase();
    return [
      for (final h in hits)
        if (h.displayName.toLowerCase().contains(needle)) h,
    ];
  }

  @override
  Future<void> checkinParticipant(TournamentParticipantId participantId) async {
    checkins.add(participantId.value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

CheckinSearchHit _hit({
  required String pid,
  required String name,
  String tournamentName = 'Frühlingscup',
  DateTime? checkedInAt,
}) {
  return CheckinSearchHit(
    participantId: TournamentParticipantId(pid),
    displayName: name,
    tournamentId: const TournamentId('t-1'),
    tournamentName: tournamentName,
    checkedInAt: checkedInAt,
  );
}

Future<_SpyRemote> _pump(
  WidgetTester tester,
  List<CheckinSearchHit> hits,
) async {
  final remote = _SpyRemote(hits);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(remote),
      ],
      child: MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CrossCheckinScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return remote;
}

void main() {
  testWidgets('typing a query renders the matching hits with their tournament',
      (tester) async {
    await _pump(tester, [
      _hit(pid: 'p1', name: 'Stefan Brunner'),
      _hit(pid: 'p2', name: 'Holzwurm Bern', tournamentName: 'Sommercup'),
    ]);

    await tester.enterText(find.byType(TextField), 'Brunner');
    await tester.pumpAndSettle();

    expect(find.text('Stefan Brunner'), findsOneWidget);
    expect(find.text('Frühlingscup'), findsOneWidget);
    // The non-matching team hit is filtered out by the (server-side) search.
    expect(find.text('Holzwurm Bern'), findsNothing);
  });

  testWidgets('tapping Einchecken dispatches the check-in for that hit',
      (tester) async {
    final remote = await _pump(tester, [
      _hit(pid: 'p1', name: 'Stefan Brunner'),
    ]);

    await tester.enterText(find.byType(TextField), 'Stefan');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Einchecken'));
    await tester.pumpAndSettle();

    expect(remote.checkins, ['p1']);
  });

  testWidgets('an already-checked-in hit shows the Anwesend state',
      (tester) async {
    await _pump(tester, [
      _hit(pid: 'p1', name: 'Stefan Brunner', checkedInAt: DateTime.utc(2026)),
    ]);

    await tester.enterText(find.byType(TextField), 'Stefan');
    await tester.pumpAndSettle();

    expect(find.text('Anwesend'), findsOneWidget);
    expect(find.text('Einchecken'), findsNothing);
  });

  testWidgets('an empty query shows the search prompt, no list', (tester) async {
    await _pump(tester, [_hit(pid: 'p1', name: 'Stefan Brunner')]);

    expect(find.text('Stefan Brunner'), findsNothing);
    final l = await AppLocalizations.delegate.load(const Locale('de'));
    expect(find.text(l.crossCheckinPrompt), findsOneWidget);
  });
}
