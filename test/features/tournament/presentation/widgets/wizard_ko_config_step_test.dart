import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/wizard_help.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/_wizard_ko_config_step.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/info_icon_button.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Hosts [WizardKoConfigStep] in a minimal MaterialApp and exposes the
/// last config that was pushed via the callback, so the test can read it
/// back without standing up the whole wizard. The step is wrapped in
/// [WizardHelp] so the per-field explainer glyphs surface (like the live
/// wizard, which flips help on via the step toggle).
class _Host extends StatefulWidget {
  const _Host({required this.draft, this.help = true, super.key});

  final TournamentConfigDraft draft;
  final bool help;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  KoPhaseConfig? lastConfig;
  SeedingMode? lastSeeding;
  late TournamentConfigDraft _draft;
  late bool _help;
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _help = widget.help;
    _container = ProviderContainer();
  }

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: WizardHelp(
          show: _help,
          child: WizardKoConfigStep(
            draft: _draft,
            controller:
                _container.read(tournamentConfigControllerProvider.notifier),
            onConfigChanged: (cfg) {
              setState(() {
                lastConfig = cfg;
                if (cfg != null) {
                  _draft = _draft.copyWith(koConfig: cfg);
                }
              });
            },
            onSeedingModeChanged: (mode) => setState(() => lastSeeding = mode),
            helpShown: _help,
            onHelpChanged: (on) => setState(() => _help = on),
          ),
        ),
      ),
    );
  }
}

Future<_HostState> _pump(
  WidgetTester tester, {
  required TournamentConfigDraft draft,
  bool help = true,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final key = GlobalKey<_HostState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('de'),
      home: _Host(key: key, draft: draft, help: help),
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

void main() {
  testWidgets(
      'smart default for 2^n participants is participantCount / 2 (U4)',
      (tester) async {
    final host = await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.roundRobinThenKo,
      ),
    );
    expect(host.lastConfig?.qualifierCount, 4);
  });

  testWidgets(
      'smart default for non-2^n participants is previous power of two (U4)',
      (tester) async {
    final host = await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        maxParticipants: 12,
        format: TournamentFormat.roundRobinThenKo,
      ),
    );
    expect(host.lastConfig?.qualifierCount, 8);
  });

  testWidgets(
      'K11: KO size selector is decoupled from maxParticipants and capped at 64',
      (tester) async {
    // Small roster (8) but the selectable KO sizes are NOT capped at the
    // roster — they span powers of two up to koBracketSizeCap (64).
    final host = await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        // Default roster of 8 — decoupled, the KO sizes still span up to 64.
        format: TournamentFormat.roundRobinThenKo,
      ),
    );
    for (final size in const [2, 4, 8, 16, 32, 64]) {
      expect(find.widgetWithText(InkWell, '$size'), findsOneWidget,
          reason: 'size $size must be offered up to the KO cap');
    }
    // Nothing above the cap, regardless of the participant count.
    expect(find.widgetWithText(InkWell, '128'), findsNothing);

    // Picking a size above the roster still works (decoupled): a 16-bracket on
    // an 8-player cap is valid now.
    await tester.tap(find.widgetWithText(InkWell, '16'));
    await tester.pumpAndSettle();
    expect(host.lastConfig?.qualifierCount, 16);
  });

  testWidgets(
      'K11: with 1000 participants the KO sizes stay capped at 64',
      (tester) async {
    await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        maxParticipants: 1000,
        format: TournamentFormat.roundRobinThenKo,
      ),
    );
    expect(find.widgetWithText(InkWell, '64'), findsOneWidget);
    expect(find.widgetWithText(InkWell, '128'), findsNothing);
    expect(find.widgetWithText(InkWell, '256'), findsNothing);
    expect(find.widgetWithText(InkWell, '512'), findsNothing);
  });

  testWidgets('Spiel um Platz 3 is always on (no toggle) (DOD-12)',
      (tester) async {
    final host = await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.roundRobinThenKo,
      ),
    );
    // withThirdPlacePlayoff is hard-wired true; no bronze switch is rendered.
    expect(host.lastConfig?.withThirdPlacePlayoff, isTrue);
    expect(find.text('Spiel um Platz 3 austragen'), findsNothing);
  });

  testWidgets(
      'no removed UI: byes preview, Mighty quali and Shoot-Out are gone',
      (tester) async {
    await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.roundRobinThenKo,
      ),
    );
    expect(find.textContaining('Bracket-Grösse'), findsNothing);
    // The old byes-preview line ("… Freilos(e) an die Top-Seeds") is gone.
    expect(find.textContaining('an die Top-Seeds'), findsNothing);
    expect(find.text('Mighty-Finisher-Quali'), findsNothing);
    // Seeding label reads "aus Vorrunde" (not "Gruppenphase").
    expect(find.text('Automatisch aus Vorrunde'), findsOneWidget);
  });

  testWidgets(
      'renders one per-round rules block per KO round (tracks qualifier count)',
      (tester) async {
    // 8 qualifiers => 3 KO rounds (Achtel/Viertel… no — bracket 8 = 3 rounds:
    // Viertelfinale, Halbfinale, Final). Seeded list has length 3.
    await _pump(
      tester,
      draft: TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.roundRobinThenKo,
        koConfig: KoPhaseConfig(qualifierCount: 8, participantCount: 8),
        koRoundFormats: const <MatchFormatSpec>[
          MatchFormatSpec(setsToWin: 2, maxSets: 3, timeLimitSeconds: 1800),
          MatchFormatSpec(setsToWin: 3, maxSets: 5, timeLimitSeconds: 3600),
          MatchFormatSpec(
            setsToWin: 3,
            maxSets: 5,
            timeLimitSeconds: 3600,
            tiebreakEnabled: false,
            finalNoTiebreak: true,
          ),
        ],
      ),
    );
    // One block per round → the round labels surface (bracket size 8).
    expect(find.text('Viertelfinale'), findsOneWidget);
    expect(find.text('Halbfinale'), findsOneWidget);
    expect(find.text('Final'), findsOneWidget);
  });

  testWidgets('editing a per-round Sätze field updates that round via the '
      'controller', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Keep the notifier alive for the whole test (otherwise it auto-disposes
    // once the synchronous reads return and `setKoRoundFormat` throws).
    container.listen(
      tournamentConfigControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    final controller =
        container.read(tournamentConfigControllerProvider.notifier);

    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final draft = TournamentConfigDraft(
      displayName: 'Cup',
      format: TournamentFormat.roundRobinThenKo,
      koConfig: KoPhaseConfig(qualifierCount: 4, participantCount: 4),
      koRoundFormats: const <MatchFormatSpec>[
        MatchFormatSpec(setsToWin: 2, maxSets: 3, timeLimitSeconds: 1800),
        MatchFormatSpec(setsToWin: 2, maxSets: 3, timeLimitSeconds: 1800),
      ],
    );
    // Seed the controller so setKoRoundFormat has a list to write into.
    controller
      ..setKoType(KoType.singleOut)
      ..setKoConfig(
        KoPhaseConfig(qualifierCount: 4, participantCount: 4),
      );

    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WizardKoConfigStep(
              draft: draft,
              controller: controller,
              onConfigChanged: (_) {},
              onSeedingModeChanged: (_) {},
              helpShown: false,
              onHelpChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The first per-round "Sätze zum Sieg" field belongs to round index 0.
    final saetze = find.widgetWithText(Row, 'Sätze zum Sieg');
    expect(saetze, findsWidgets);
    final field = find
        .descendant(of: saetze.first, matching: find.byType(TextField))
        .first;
    await tester.enterText(field, '3');
    await tester.pumpAndSettle();

    expect(container.read(tournamentConfigControllerProvider)
        .koRoundFormats.first.setsToWin, 3);
  });

  testWidgets('bracket-size info button opens its explainer dialog',
      (tester) async {
    await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.roundRobinThenKo,
      ),
    );
    // The info glyph sits in the same row as the bracket-size label.
    final info = find.descendant(
      of: find.ancestor(
        of: find.text('Anzahl Qualifikanten'),
        matching: find.byType(Row),
      ),
      matching: find.byIcon(LucideIcons.info),
    );
    expect(info, findsOneWidget);
    await tester.tap(info);
    await tester.pumpAndSettle();
    expect(find.text('Wie viele Teams im K.-o.'), findsOneWidget);
    expect(
      find.textContaining('eine Zweierpotenz'),
      findsOneWidget,
    );
  });

  testWidgets('seeding-source info explains both auto and manual',
      (tester) async {
    await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.roundRobinThenKo,
      ),
    );
    final info = find.descendant(
      of: find.ancestor(
        of: find.text('Seeding-Quelle'),
        matching: find.byType(Row),
      ),
      matching: find.byIcon(LucideIcons.info),
    );
    expect(info, findsOneWidget);
    await tester.tap(info);
    await tester.pumpAndSettle();
    // The single dialog covers both options and the manual screen hint.
    expect(find.textContaining('Automatisch aus Vorrunde:'), findsOneWidget);
    expect(find.textContaining('eigenen Setzlisten-Screen'), findsOneWidget);
  });

  testWidgets('consolation name and direct-starter lost their info glyphs',
      (tester) async {
    // Even with help on, the Trostturnier fields are glyph-free now: the
    // direct-starter helper and the self-explanatory name carry the meaning.
    await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.roundRobinThenKo,
        koType: KoType.consolation,
      ),
    );
    for (final label in const [
      'Name des Trostturniers',
      'Direkt ins Trostturnier',
    ]) {
      final info = find.descendant(
        of: find.ancestor(
          of: find.text(label),
          matching: find.byType(Row),
        ),
        matching: find.byIcon(LucideIcons.info),
      );
      expect(info, findsNothing, reason: 'glyph for "$label" should be gone');
    }
  });

  testWidgets('the four retained glyphs surface in help mode', (tester) async {
    await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.roundRobinThenKo,
      ),
    );
    for (final label in const [
      'Anzahl Qualifikanten',
      'Seeding-Quelle',
      'Begegnungen',
      'KO-Tiebreak-Methode',
    ]) {
      final info = find.descendant(
        of: find.ancestor(
          of: find.text(label),
          matching: find.byType(Row),
        ),
        matching: find.byIcon(LucideIcons.info),
      );
      expect(info, findsOneWidget, reason: 'glyph for "$label" must show');
    }
  });

  testWidgets('glyphs stay hidden until help mode is on', (tester) async {
    await _pump(
      tester,
      help: false,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.roundRobinThenKo,
      ),
    );
    // No glyph with help off — the toggle gates every field explainer.
    expect(find.byType(InfoIconButton), findsNothing);

    // Flip the step's own "Erklärungen" toggle: glyphs appear.
    await tester.tap(find.text('Erklärungen'));
    await tester.pumpAndSettle();
    expect(find.byType(InfoIconButton), findsWidgets);
  });

  testWidgets('the KO system choice and its compare-models link live here now',
      (tester) async {
    await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.roundRobinThenKo,
      ),
    );
    // The KO-system label, all three options and the compare-models link sit
    // in the KO step (they used to live on the format step).
    expect(find.text('K.-o.-System'), findsOneWidget);
    expect(find.text('Single-Out'), findsOneWidget);
    expect(find.text('Double-Elimination'), findsOneWidget);
    expect(find.text('Trostturnier'), findsOneWidget);
    expect(find.text('Modelle vergleichen'), findsOneWidget);
  });

  testWidgets('picking a KO system flows through the controller (koType + '
      'bracketType)', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(
      tournamentConfigControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    final controller =
        container.read(tournamentConfigControllerProvider.notifier);

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WizardKoConfigStep(
              draft: const TournamentConfigDraft(
                displayName: 'Cup',
                format: TournamentFormat.roundRobinThenKo,
              ),
              controller: controller,
              onConfigChanged: (_) {},
              onSeedingModeChanged: (_) {},
              helpShown: false,
              onHelpChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Double-Elimination'));
    await tester.pumpAndSettle();

    final state = container.read(tournamentConfigControllerProvider);
    expect(state.koType, KoType.doubleOut);
    // bracketType is derived from the KO type, so the choice propagates.
    expect(state.bracketType, BracketType.doubleElimination);
  });
}
