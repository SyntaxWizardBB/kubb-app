import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/schoch_config_section.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/wizard_number_field.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Hosts [SchochConfigSection] in a minimal MaterialApp and threads the
/// reported rounds back in, so a typed value drives the visible state the
/// same way the wizard step does.
class _Host extends StatefulWidget {
  const _Host({required this.initialRounds, super.key});

  final int initialRounds;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int rounds = widget.initialRounds;
  int? lastReported;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SchochConfigSection(
        participantCount: 16,
        rounds: rounds,
        onRoundsChanged: (v) => setState(() {
          rounds = v;
          lastReported = v;
        }),
      ),
    );
  }
}

Future<_HostState> _pump(WidgetTester tester, {required int rounds}) async {
  final key = GlobalKey<_HostState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('de'),
      home: _Host(key: key, initialRounds: rounds),
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

void main() {
  testWidgets('renders a number input, no slider', (tester) async {
    await _pump(tester, rounds: 7);
    expect(find.byType(WizardNumberField), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('typing a value sets the rounds', (tester) async {
    final host = await _pump(tester, rounds: 7);

    await tester.enterText(find.byType(TextField), '6');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(host.lastReported, 6);
    expect(host.rounds, 6);
  });

  testWidgets('a value above the max clamps back to roundsMax',
      (tester) async {
    final host = await _pump(tester, rounds: 7);

    await tester.enterText(
      find.byType(TextField),
      '${SchochConfigSection.roundsMax + 3}',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(host.rounds, SchochConfigSection.roundsMax);
  });
}
