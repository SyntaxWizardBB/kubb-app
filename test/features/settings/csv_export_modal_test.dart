import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/settings/application/csv_export_notifier.dart';
import 'package:kubb_app/features/settings/application/csv_export_state.dart';
import 'package:kubb_app/features/settings/presentation/csv_export_modal.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class _StubNotifier extends CsvExportNotifier {
  _StubNotifier(this._initial);
  final CsvExportState _initial;

  @override
  Future<CsvExportState> build() async => _initial;
}

void main() {
  Future<void> pumpModal(
    WidgetTester tester, {
    required int count,
  }) async {
    final initial = CsvExportState(count: count);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          csvExportProvider.overrideWith(() => _StubNotifier(initial)),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => CsvExportModal.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('disables download button when no sessions', (tester) async {
    await pumpModal(tester, count: 0);

    final download = find.text('Herunterladen');
    expect(download, findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(of: download, matching: find.byType(FilledButton)),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Keine Sessions zum Exportieren'), findsOneWidget);
  });

  testWidgets('enables download button when sessions exist', (tester) async {
    await pumpModal(tester, count: 5);

    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Herunterladen'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNotNull);
    expect(find.text('5 Sessions im Filter'), findsOneWidget);
  });
}
