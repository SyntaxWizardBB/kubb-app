import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_field.dart';
import 'package:kubb_app/core/ui/widgets/wizard_help.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/info_icon_button.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

Widget _host({required bool help}) {
  return MaterialApp(
    theme: KubbTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: WizardHelp(
        show: help,
        child: const KubbField(
          label: 'Teamgrösse',
          helper: 'Mindestzahl pro Team',
          info: InfoIconButton(title: 'Teamgrösse', message: 'Erklärungstext'),
          child: SizedBox(key: Key('control'), height: 20),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders label, helper and the child control', (tester) async {
    await tester.pumpWidget(_host(help: false));

    expect(find.text('Teamgrösse'), findsOneWidget);
    expect(find.text('Mindestzahl pro Team'), findsOneWidget);
    expect(find.byKey(const Key('control')), findsOneWidget);
  });

  testWidgets('hides the info glyph while help mode is off', (tester) async {
    await tester.pumpWidget(_host(help: false));

    expect(find.byType(InfoIconButton), findsNothing);
  });

  testWidgets('shows the info glyph once help mode is on', (tester) async {
    await tester.pumpWidget(_host(help: true));

    expect(find.byType(InfoIconButton), findsOneWidget);
  });

  testWidgets('tapping the glyph opens the explainer bottom sheet',
      (tester) async {
    await tester.pumpWidget(_host(help: true));

    await tester.tap(find.byType(InfoIconButton));
    await tester.pumpAndSettle();

    expect(find.text('Erklärungstext'), findsOneWidget);
  });

  testWidgets('tapping the label opens the same sheet in help mode',
      (tester) async {
    await tester.pumpWidget(_host(help: true));

    await tester.tap(find.text('Teamgrösse'));
    await tester.pumpAndSettle();

    expect(find.text('Erklärungstext'), findsOneWidget);
  });

  testWidgets('errorText replaces the helper line', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: WizardHelp(
            show: false,
            child: KubbField(
              label: 'Feld',
              helper: 'Hinweis',
              errorText: 'Pflichtfeld',
              child: SizedBox(height: 20),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Pflichtfeld'), findsOneWidget);
    expect(find.text('Hinweis'), findsNothing);
  });

  testWidgets('optional badge appears when optional is set', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: WizardHelp(
            show: false,
            child: KubbField(
              label: 'Telefon',
              optional: true,
              child: SizedBox(height: 20),
            ),
          ),
        ),
      ),
    );

    expect(find.text('optional'), findsOneWidget);
  });
}
