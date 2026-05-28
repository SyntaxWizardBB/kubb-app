import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_chip.dart';
import 'package:lucide_icons/lucide_icons.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(KubbTokens.space4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [child],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Material findInnerMaterial(WidgetTester tester) {
    return tester.widget<Material>(
      find.descendant(of: find.byType(KubbChip), matching: find.byType(Material)).first,
    );
  }

  testWidgets('renders label text and honours min-height 32dp', (tester) async {
    await pump(
      tester,
      const KubbChip(tone: KubbChipTone.neutral, label: 'Standard'),
    );

    expect(find.text('Standard'), findsOneWidget);
    final size = tester.getSize(find.byType(KubbChip));
    expect(size.height, greaterThanOrEqualTo(KubbChip.minHeight));
  });

  testWidgets('icon is rendered when provided', (tester) async {
    await pump(
      tester,
      const KubbChip(
        tone: KubbChipTone.heli,
        label: 'Helikopter',
        icon: LucideIcons.fan,
      ),
    );
    expect(find.byIcon(LucideIcons.fan), findsOneWidget);
  });

  testWidgets('hit tone paints meadow-100 background', (tester) async {
    await pump(
      tester,
      const KubbChip(tone: KubbChipTone.hit, label: 'Sniper'),
    );
    expect(findInnerMaterial(tester).color, KubbTokens.meadow100);
  });

  testWidgets('miss tone paints custom miss surface', (tester) async {
    await pump(
      tester,
      const KubbChip(tone: KubbChipTone.miss, label: 'Strafkubb'),
    );
    expect(findInnerMaterial(tester).color, const Color(0xFFF8E2DD));
  });

  testWidgets('heli tone paints wood-100 background', (tester) async {
    await pump(
      tester,
      const KubbChip(tone: KubbChipTone.heli, label: 'Helikopter'),
    );
    expect(findInnerMaterial(tester).color, KubbTokens.wood100);
  });

  testWidgets('penalty tone paints miss surface with penalty fg', (tester) async {
    await pump(
      tester,
      const KubbChip(tone: KubbChipTone.penalty, label: 'Penalty'),
    );
    expect(findInnerMaterial(tester).color, const Color(0xFFF8E2DD));
  });

  testWidgets('king tone paints king gold background', (tester) async {
    await pump(
      tester,
      const KubbChip(tone: KubbChipTone.king, label: 'König'),
    );
    expect(findInnerMaterial(tester).color, KubbTokens.king);
  });

  testWidgets('info tone paints meadow-500 solid background', (tester) async {
    await pump(
      tester,
      const KubbChip(tone: KubbChipTone.info, label: '8 m · aktiv'),
    );
    expect(findInnerMaterial(tester).color, KubbTokens.meadow500);
  });

  testWidgets('neutral tone paints stone-100 background', (tester) async {
    await pump(
      tester,
      const KubbChip(tone: KubbChipTone.neutral, label: 'Match'),
    );
    expect(findInnerMaterial(tester).color, KubbTokens.stone100);
  });
}
