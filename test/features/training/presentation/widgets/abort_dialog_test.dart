import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/training/presentation/widgets/abort_dialog.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  Future<void> openDialog(WidgetTester tester, {required bool hasThrows}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => AbortDialog.show(context, hasThrows: hasThrows),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows save button when session has throws', (tester) async {
    await openDialog(tester, hasThrows: true);
    expect(find.text('Speichern'), findsOneWidget);
    expect(find.text('Verwerfen'), findsOneWidget);
    expect(find.text('Zurück'), findsOneWidget);
  });

  testWidgets('hides save button when session has no throws', (tester) async {
    await openDialog(tester, hasThrows: false);
    expect(find.text('Speichern'), findsNothing);
    expect(find.text('Verwerfen'), findsOneWidget);
    expect(find.text('Zurück'), findsOneWidget);
  });
}
