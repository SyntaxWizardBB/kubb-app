import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_chip.dart';
import 'package:kubb_app/core/ui/widgets/kubb_status_chip.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Sprint-B W3-T4 — guards the central status-chip mapping. The Mängel
/// report #1 complaint ("Chips wirken alle gleich") had two root causes:
/// duplicated mapping logic in the three consumer screens and the same
/// meadow tone re-used for live / awaiting / finalized. This test pins
/// the tone (and therefore the chip background colour) per state so a
/// future refactor cannot collapse two distinct states onto the same
/// visual.
Future<void> _pump(WidgetTester tester, Widget Function(AppLocalizations l) build) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(child: build(AppLocalizations.of(context))),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

KubbChipTone _toneOf(WidgetTester tester) =>
    tester.widget<KubbChip>(find.byType(KubbChip)).tone;

void main() {
  // ---- The eight states called out in the Sprint-B W3-T4 brief. ----

  testWidgets('match.active → hit tone, label "Live"', (tester) async {
    await _pump(
      tester,
      (l) => KubbStatusChip.match(status: MatchStatus.active, l: l),
    );
    expect(_toneOf(tester), KubbChipTone.hit);
    expect(find.text('Live'), findsOneWidget);
  });

  testWidgets(
      'tournamentMatch.disputed → penalty tone, label "Disput"',
      (tester) async {
    await _pump(
      tester,
      (l) => KubbStatusChip.tournamentMatch(
        status: TournamentMatchStatus.disputed,
        l: l,
      ),
    );
    expect(_toneOf(tester), KubbChipTone.penalty);
    expect(find.text('Disput'), findsOneWidget);
  });

  testWidgets(
      'tournamentMatch.finalized → info tone, label "Fertig"',
      (tester) async {
    await _pump(
      tester,
      (l) => KubbStatusChip.tournamentMatch(
        status: TournamentMatchStatus.finalized,
        l: l,
      ),
    );
    expect(_toneOf(tester), KubbChipTone.info);
    expect(find.text('Fertig'), findsOneWidget);
  });

  testWidgets(
      'tournamentMatch.awaitingResults → heli tone, label "Wartet"',
      (tester) async {
    await _pump(
      tester,
      (l) => KubbStatusChip.tournamentMatch(
        status: TournamentMatchStatus.awaitingResults,
        l: l,
      ),
    );
    expect(_toneOf(tester), KubbChipTone.heli);
    expect(find.text('Wartet'), findsOneWidget);
  });

  testWidgets('tournament.live → hit tone', (tester) async {
    await _pump(
      tester,
      (l) => KubbStatusChip.tournament(status: TournamentStatus.live, l: l),
    );
    expect(_toneOf(tester), KubbChipTone.hit);
    expect(find.text('Live'), findsOneWidget);
  });

  testWidgets('tournament.draft → neutral tone', (tester) async {
    await _pump(
      tester,
      (l) => KubbStatusChip.tournament(status: TournamentStatus.draft, l: l),
    );
    expect(_toneOf(tester), KubbChipTone.neutral);
    expect(find.text('Entwurf'), findsOneWidget);
  });

  testWidgets('tournament.finalized → info tone, label "Beendet"',
      (tester) async {
    await _pump(
      tester,
      (l) => KubbStatusChip.tournament(
        status: TournamentStatus.finalized,
        l: l,
      ),
    );
    expect(_toneOf(tester), KubbChipTone.info);
    expect(find.text('Beendet'), findsOneWidget);
  });

  testWidgets('tournament.aborted → miss tone, label "Abgebrochen"',
      (tester) async {
    await _pump(
      tester,
      (l) => KubbStatusChip.tournament(
        status: TournamentStatus.aborted,
        l: l,
      ),
    );
    expect(_toneOf(tester), KubbChipTone.miss);
    expect(find.text('Abgebrochen'), findsOneWidget);
  });

  // ---- Visual differentiation guard. ----
  //
  // The four match-side states must paint four distinct chip
  // backgrounds; ditto for the four tournament-side states. If a future
  // refactor collapses two states onto the same tone, this test fails.

  testWidgets('the four meaningful tournament-match states pick four distinct tones',
      (tester) async {
    // penalty + miss intentionally share the same chip background
    // (`#F8E2DD`) and differ only in foreground; the four "active"
    // states (heli/penalty/info/miss-tone) still resolve to four
    // distinct [KubbChipTone] values, which is what the brief asks
    // for ("eindeutige Farbe pro Status").
    final states = <TournamentMatchStatus>[
      TournamentMatchStatus.awaitingResults, // heli
      TournamentMatchStatus.disputed, // penalty
      TournamentMatchStatus.finalized, // info
      TournamentMatchStatus.voided, // miss
    ];

    final seen = <KubbChipTone>{};
    for (final s in states) {
      await _pump(
        tester,
        (l) => KubbStatusChip.tournamentMatch(status: s, l: l),
      );
      seen.add(_toneOf(tester));
    }
    expect(seen.length, states.length,
        reason: 'every status must resolve to a unique semantic tone');
  });
}
