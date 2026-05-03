import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_tap_pad.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(KubbTokens.space4),
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('fires onTap callback when tapped', (tester) async {
    var taps = 0;
    await pump(
      tester,
      KubbTapPad(
        label: 'Hit',
        sign: '+',
        tone: KubbTapPadTone.hit,
        onTap: () => taps++,
      ),
    );

    await tester.tap(find.byType(KubbTapPad));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('hit tone paints background with KubbTokens.hit', (tester) async {
    await pump(
      tester,
      KubbTapPad(
        label: 'Hit',
        sign: '+',
        tone: KubbTapPadTone.hit,
        onTap: () {},
      ),
    );

    final material = tester.widget<Material>(
      find.descendant(of: find.byType(KubbTapPad), matching: find.byType(Material)).first,
    );
    expect(material.color, KubbTokens.hit);
  });

  testWidgets('honours minimum tap height of 84dp', (tester) async {
    await pump(
      tester,
      KubbTapPad(
        label: 'Heli',
        sign: '+',
        tone: KubbTapPadTone.heli,
        onTap: () {},
      ),
    );

    final size = tester.getSize(find.byType(KubbTapPad));
    expect(size.height, greaterThanOrEqualTo(KubbTapPad.minHeight));
  });
}
