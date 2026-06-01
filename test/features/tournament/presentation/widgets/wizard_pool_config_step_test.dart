import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/_wizard_pool_config_step.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Hosts [WizardPoolConfigStep] in a minimal MaterialApp and threads the
/// pushed pitch plan back into the draft, so the test can assert the
/// per-group assignment without standing up the whole wizard.
class _Host extends StatefulWidget {
  const _Host({required this.draft, super.key});

  final TournamentConfigDraft draft;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late TournamentConfigDraft _draft = widget.draft;
  PoolPhaseConfig? lastConfig;

  PitchPlan? get pitchPlan => _draft.pitchPlan;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: WizardPoolConfigStep(
          draft: _draft,
          onConfigChanged: (cfg) => setState(() => lastConfig = cfg),
          onPitchPlanChanged: (plan) =>
              setState(() => _draft = _draft.copyWith(pitchPlan: plan)),
        ),
      ),
    );
  }
}

Future<_HostState> _pump(
  WidgetTester tester, {
  required TournamentConfigDraft draft,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
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
      'tapping a pitch chip for group A updates pitchPlan.groupAssignment',
      (tester) async {
    final host = await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.roundRobinThenKo,
        pitchPlan: PitchPlan(mode: PitchMode.range, rangeFrom: 1, rangeTo: 3),
      ),
    );

    // Section header renders because a plan + valid group count exist.
    expect(find.text('Pitch-Zuteilung pro Gruppe'), findsOneWidget);
    // No assignment yet.
    expect(host.pitchPlan!.groupAssignment, isEmpty);

    // Group A is the first group block; tap its pitch "2" chip.
    final groupAFinder = find.ancestor(
      of: find.text('Gruppe A'),
      matching: find.byType(Column),
    );
    final chip = find.descendant(
      of: groupAFinder.first,
      matching: find.widgetWithText(InkWell, '2'),
    );
    await tester.tap(chip.first);
    await tester.pumpAndSettle();

    expect(host.pitchPlan!.groupAssignment, <String, List<int>>{
      'A': <int>[2],
    });
  });

  testWidgets('no assignment section without a pitch plan', (tester) async {
    final host = await _pump(
      tester,
      draft: const TournamentConfigDraft(
        displayName: 'Cup',
        format: TournamentFormat.roundRobinThenKo,
      ),
    );
    expect(find.text('Pitch-Zuteilung pro Gruppe'), findsNothing);
    expect(host.pitchPlan, isNull);
  });
}
