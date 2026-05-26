import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
// ignore: implementation_imports — Test exercises private wizard helper.
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/_wizard_ko_config_step.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Hosts [WizardKoConfigStep] in a minimal MaterialApp and exposes the
/// last config that was pushed via the callback, so the test can read it
/// back without standing up the whole wizard.
class _Host extends StatefulWidget {
  const _Host({super.key, required this.draft});

  final TournamentConfigDraft draft;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  KoPhaseConfig? lastConfig;
  SeedingMode? lastSeeding;
  late TournamentConfigDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: WizardKoConfigStep(
          draft: _draft,
          onConfigChanged: (cfg) {
            setState(() {
              lastConfig = cfg;
              if (cfg != null) {
                _draft = _draft.copyWith(koConfig: cfg);
              }
            });
          },
          onSeedingModeChanged: (mode) => setState(() => lastSeeding = mode),
        ),
      ),
    );
  }
}

Future<_HostState> _pump(
  WidgetTester tester, {
  required TournamentConfigDraft draft,
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
      home: _Host(key: key, draft: draft),
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
        maxParticipants: 8,
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
      'preview for n=6 of 12 shows bracket 8, 2 BYEs, 4 real matches (U3)',
      (tester) async {
    await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        maxParticipants: 12,
        format: TournamentFormat.roundRobinThenKo,
      ),
    );
    await tester.enterText(find.byType(TextField), '6');
    await tester.pumpAndSettle();

    expect(find.text('Bracket-Grösse: 8'), findsOneWidget);
    expect(find.text('Davon 2 Freilos(e) an die Top-Seeds'), findsOneWidget);
    expect(find.text('Runde 1: 4 echte Spiele'), findsOneWidget);
  });

  testWidgets('out-of-range qualifier count clears the pushed config (U2)',
      (tester) async {
    final host = await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        maxParticipants: 8,
        format: TournamentFormat.roundRobinThenKo,
      ),
    );
    // Below the minimum of 2.
    await tester.enterText(find.byType(TextField), '1');
    await tester.pumpAndSettle();
    expect(host.lastConfig, isNull);
    // Above participantCount.
    await tester.enterText(find.byType(TextField), '99');
    await tester.pumpAndSettle();
    expect(host.lastConfig, isNull);
    // Back in range.
    await tester.enterText(find.byType(TextField), '4');
    await tester.pumpAndSettle();
    expect(host.lastConfig?.qualifierCount, 4);
  });

  testWidgets('bronze switch pre-fills from suggestedWithThirdPlacePlayoff',
      (tester) async {
    final host = await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        maxParticipants: 8,
        format: TournamentFormat.roundRobinThenKo,
        leagueEligible: true,
      ),
    );
    expect(host.lastConfig?.withThirdPlacePlayoff, isTrue);
  });
}
