import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_bottom_sheet.dart';

void main() {
  testWidgets('helper opens sheet with grabber and rounded top radii',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showKubbBottomSheet<void>(
                  ctx,
                  builder: (_) => const Padding(
                    padding: EdgeInsets.all(KubbTokens.space4),
                    child: Text('sheet-content'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('sheet-content'), findsOneWidget);
    expect(find.byType(KubbBottomSheet), findsOneWidget);

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(KubbBottomSheet),
        matching: find.byType(Container),
      ).first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(
      decoration.borderRadius,
      const BorderRadius.vertical(top: Radius.circular(KubbTokens.radiusXl)),
    );

    final grabberFinder = find.descendant(
      of: find.byType(KubbBottomSheet),
      matching: find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final deco = w.decoration;
        if (deco is! BoxDecoration) return false;
        return deco.borderRadius ==
            BorderRadius.circular(KubbTokens.radiusPill);
      }),
    );
    expect(grabberFinder, findsOneWidget);
  });
}
