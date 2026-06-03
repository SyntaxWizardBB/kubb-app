import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/bracket_canvas.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/kubb_match_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _id = TournamentId('t-1');
final _bracket = Bracket.singleElimination(
  const ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'],
);

/// A consolation tree with two rounds (R1 = 2 pairings, R2 = consolation final)
/// plus a consolation third-place playoff — exactly the shape `bracketFromMatches`
/// projects from `consolation` + `consolation_third_place` rows (ADR-0028 §7.3).
ConsolationBracket _consolationBracket() => bracketFromMatches(<KoMatchRow>[
      (
        roundNumber: 1,
        bracketPosition: 1,
        phase: BracketPhase.consolation,
        participantA: 'cE',
        participantB: 'cF',
        winnerParticipantId: null,
        isBye: false,
      ),
      (
        roundNumber: 1,
        bracketPosition: 2,
        phase: BracketPhase.consolation,
        participantA: 'cG',
        participantB: 'cH',
        winnerParticipantId: null,
        isBye: false,
      ),
      (
        roundNumber: 2,
        bracketPosition: 1,
        phase: BracketPhase.consolation,
        participantA: 'cE',
        participantB: 'cG',
        winnerParticipantId: null,
        isBye: false,
      ),
      (
        roundNumber: 1,
        bracketPosition: 1,
        phase: BracketPhase.consolationThirdPlace,
        participantA: 'cF',
        participantB: 'cH',
        winnerParticipantId: null,
        isBye: false,
      ),
    ]) as ConsolationBracket;

/// A consolation tree that ALSO carries the single-elim main tree in
/// `mainRounds` — exactly what `bracketFromMatches` now projects from mixed
/// `ko`/`final`/`third_place` + `consolation` rows (ADR-0028 §7.3 / DoD-06).
ConsolationBracket _consolationWithMain() => bracketFromMatches(<KoMatchRow>[
      // --- Main tree: 4er bracket (semis + final) + 3rd-place playoff.
      (
        roundNumber: 1,
        bracketPosition: 1,
        phase: BracketPhase.winners,
        participantA: 'mA',
        participantB: 'mD',
        winnerParticipantId: null,
        isBye: false,
      ),
      (
        roundNumber: 1,
        bracketPosition: 2,
        phase: BracketPhase.winners,
        participantA: 'mB',
        participantB: 'mC',
        winnerParticipantId: null,
        isBye: false,
      ),
      (
        roundNumber: 2,
        bracketPosition: 1,
        phase: BracketPhase.finals,
        participantA: 'mA',
        participantB: 'mB',
        winnerParticipantId: null,
        isBye: false,
      ),
      (
        roundNumber: 1,
        bracketPosition: 1,
        phase: BracketPhase.thirdPlace,
        participantA: 'mD',
        participantB: 'mC',
        winnerParticipantId: null,
        isBye: false,
      ),
      // --- Consolation tree: R1 (2 pairings) + final + 3rd-place playoff.
      (
        roundNumber: 1,
        bracketPosition: 1,
        phase: BracketPhase.consolation,
        participantA: 'cE',
        participantB: 'cF',
        winnerParticipantId: null,
        isBye: false,
      ),
      (
        roundNumber: 1,
        bracketPosition: 2,
        phase: BracketPhase.consolation,
        participantA: 'cG',
        participantB: 'cH',
        winnerParticipantId: null,
        isBye: false,
      ),
      (
        roundNumber: 2,
        bracketPosition: 1,
        phase: BracketPhase.consolation,
        participantA: 'cE',
        participantB: 'cG',
        winnerParticipantId: null,
        isBye: false,
      ),
      (
        roundNumber: 1,
        bracketPosition: 1,
        phase: BracketPhase.consolationThirdPlace,
        participantA: 'cF',
        participantB: 'cH',
        winnerParticipantId: null,
        isBye: false,
      ),
    ]) as ConsolationBracket;

Future<void> _pumpCanvas(
  WidgetTester tester,
  Widget child,
) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Finds the [KubbMatchCard] whose Semantics label mentions [participant].
Finder _cardWith(String participant) => find.byWidgetPredicate(
      (w) => w is KubbMatchCard &&
          (w.pairing.$1.participantId == participant ||
              w.pairing.$2.participantId == participant),
    );

class _Handle {
  String? lastPushed;
}

Future<_Handle> _pump(WidgetTester tester, {bool editable = true}) async {
  final h = _Handle();
  final router = GoRouter(
    initialLocation: '/tournament/t-1/bracket',
    routes: [
      GoRoute(
        path: '/tournament/:id/bracket',
        builder: (_, _) => Scaffold(
          body: BracketCanvas(
            bracket: _bracket,
            editable: editable,
            tournamentId: _id,
          ),
        ),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId',
        builder: (_, s) {
          h.lastPushed =
              '/tournament/${s.pathParameters['id']}/match/${s.pathParameters['matchId']}';
          return const Scaffold(body: Text('match-route'));
        },
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp.router(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return h;
}

void main() {
  testWidgets('8-team bracket renders 7 KubbMatchCard widgets', (tester) async {
    await _pump(tester);
    expect(find.byType(KubbMatchCard), findsNWidgets(7));
  });

  testWidgets('tap on match card navigates to /<id>/match/<matchId>',
      (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.byType(KubbMatchCard).first);
    await tester.pumpAndSettle();
    expect(h.lastPushed, startsWith('/tournament/t-1/match/'));
  });

  testWidgets('read-only mode does not open override dialog on tap',
      (tester) async {
    await _pump(tester, editable: false);
    await tester.tap(find.byType(KubbMatchCard).first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  group('ConsolationBracket (Trostturnier, Modell B)', () {
    testWidgets('renders both sections via a SegmentedButton (DoD-04/05)',
        (tester) async {
      final main = Bracket.singleElimination(
        const ['mA', 'mB', 'mC', 'mD'],
        withThirdPlace: true,
      ) as SingleEliminationBracket;
      await _pumpCanvas(
        tester,
        BracketCanvas(
          bracket: _consolationBracket(),
          mainBracket: main,
          editable: false,
          tournamentId: _id,
        ),
      );

      // The switch control exists with both segments.
      expect(
        find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith(
              'SegmentedButton<',
            )),
        findsOneWidget,
      );
      expect(find.text('Hauptbaum'), findsOneWidget);
      // Trost segment label = consolation fallback name (DoD-06).
      expect(find.text('Trostturnier'), findsOneWidget);

      // Initially the main tree is visible (DoD-05): a main-bracket card.
      expect(_cardWith('mA'), findsOneWidget);
      // ...and no consolation card is rendered yet.
      expect(_cardWith('cE'), findsNothing);

      // Switch to the Trost section.
      await tester.tap(find.text('Trostturnier'));
      await tester.pumpAndSettle();
      // cE appears in the consolation R1 and the consolation final -> >= 1.
      expect(_cardWith('cE'), findsWidgets);
      expect(_cardWith('mA'), findsNothing);

      // Switch back to the Hauptbaum.
      await tester.tap(find.text('Hauptbaum'));
      await tester.pumpAndSettle();
      expect(_cardWith('mA'), findsOneWidget);
    });

    testWidgets('Trost section shows consolation final and 3rd-place (DoD-07)',
        (tester) async {
      await _pumpCanvas(
        tester,
        BracketCanvas(
          bracket: _consolationBracket(),
          editable: false,
          tournamentId: _id,
        ),
      );
      await tester.tap(find.text('Trostturnier'));
      await tester.pumpAndSettle();

      final cards = tester.widgetList<KubbMatchCard>(find.byType(KubbMatchCard));
      // Consolation final (places 5/6) = the last consolation round, projected
      // as the finals box with matchId 'r2-m0' (pairing cE/cG).
      final consFinal = cards.firstWhere((c) => c.matchId == 'r2-m0');
      expect(
        consFinal.pairing.$1.participantId == 'cE' ||
            consFinal.pairing.$2.participantId == 'cG',
        isTrue,
        reason: 'consolation final renders the last-round pairing',
      );
      // Consolation third-place (places 7/8): reuses the existing third-place
      // box (matchId 'third-place', pairing cF/cH) — DoD-07.
      final thirdPlace =
          cards.where((c) => c.matchId == 'third-place').toList();
      expect(thirdPlace, hasLength(1));
      expect(
        thirdPlace.single.pairing.$1.participantId == 'cF' &&
            thirdPlace.single.pairing.$2.participantId == 'cH',
        isTrue,
      );
    });

    testWidgets('Trost section carries the consolation name when provided',
        (tester) async {
      await _pumpCanvas(
        tester,
        BracketCanvas(
          bracket: _consolationBracket(),
          consolationName: 'Bâton Rouille',
          editable: false,
          tournamentId: _id,
        ),
      );
      // Named segment takes precedence over the fallback (DoD-06).
      expect(find.text('Bâton Rouille'), findsOneWidget);
      expect(find.text('Trostturnier'), findsNothing);
    });

    testWidgets(
        'opens on the Trost section when no main tree is supplied '
        '(reviewer finding: real tree visible by default)', (tester) async {
      await _pumpCanvas(
        tester,
        BracketCanvas(
          bracket: _consolationBracket(),
          editable: false,
          tournamentId: _id,
        ),
      );
      // Without a main tree the canvas defaults to the consolation section so
      // the only renderable tree is visible immediately (no empty hint page).
      expect(_cardWith('cE'), findsWidgets);
      // Switching to the Hauptbaum then shows the precise unavailable hint.
      await tester.tap(find.text('Hauptbaum'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Der Hauptbaum ist hier nicht verfügbar. '
          'Endplatzierungen 1–4 siehe Turnier-Detail.',
        ),
        findsOneWidget,
      );
    });

    const hintText = 'Der Hauptbaum ist hier nicht verfügbar. '
        'Endplatzierungen 1–4 siehe Turnier-Detail.';

    testWidgets(
        'main section renders the real main tree from mainRounds (DoD-08/09/10)',
        (tester) async {
      await _pumpCanvas(
        tester,
        BracketCanvas(
          bracket: _consolationWithMain(),
          editable: false,
          tournamentId: _id,
        ),
      );

      // Initial segment is the Hauptbaum (mainRounds present, DoD-10) and it
      // shows real main-bracket cards, not the unavailable hint (DoD-08/09).
      // 'mA' appears in the main semifinal AND the final pairing -> findsWidgets.
      expect(_cardWith('mA'), findsWidgets);
      expect(find.text(hintText), findsNothing);
      expect(_cardWith('cE'), findsNothing);

      // Switch to Trost: consolation cards appear, main cards gone.
      await tester.tap(find.text('Trostturnier'));
      await tester.pumpAndSettle();
      expect(_cardWith('cE'), findsWidgets);
      expect(_cardWith('mA'), findsNothing);

      // Switch back to Hauptbaum: real main tree again, still no hint.
      await tester.tap(find.text('Hauptbaum'));
      await tester.pumpAndSettle();
      expect(_cardWith('mA'), findsWidgets);
      expect(find.text(hintText), findsNothing);
    });

    testWidgets(
        'hint is the fallback only when mainRounds are empty (DoD-09)',
        (tester) async {
      // Consolation-only bracket (no mainRounds): Hauptbaum shows the hint.
      await _pumpCanvas(
        tester,
        BracketCanvas(
          bracket: _consolationBracket(),
          editable: false,
          tournamentId: _id,
        ),
      );
      await tester.tap(find.text('Hauptbaum'));
      await tester.pumpAndSettle();
      expect(find.text(hintText), findsOneWidget);
    });
  });
}
