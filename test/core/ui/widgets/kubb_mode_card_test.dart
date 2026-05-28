import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_mode_card.dart';
import 'package:lucide_icons/lucide_icons.dart';

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

  testWidgets('renders title, subtitle and icon', (tester) async {
    await pump(
      tester,
      KubbModeCard(
        title: 'Sniper',
        subtitle: 'Trefferquote · Konstanz',
        icon: LucideIcons.target,
        onTap: () {},
      ),
    );

    expect(find.text('Sniper'), findsOneWidget);
    expect(find.text('Trefferquote · Konstanz'), findsOneWidget);
    expect(find.byIcon(LucideIcons.target), findsOneWidget);
  });

  testWidgets('fires onTap when enabled', (tester) async {
    var taps = 0;
    await pump(
      tester,
      KubbModeCard(
        title: 'Finisseur',
        subtitle: 'Match-Endspiel',
        icon: LucideIcons.flag,
        onTap: () => taps++,
      ),
    );

    await tester.tap(find.byType(KubbModeCard));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('press-state animates scale down to 0.98 and back', (tester) async {
    await pump(
      tester,
      KubbModeCard(
        title: 'Match',
        subtitle: 'Mehrspieler',
        icon: LucideIcons.swords,
        onTap: () {},
      ),
    );

    final scaleFinder = find.descendant(
      of: find.byType(KubbModeCard),
      matching: find.byType(AnimatedScale),
    );
    expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(KubbModeCard)),
    );
    // InkWell highlight is debounced — let the press settle.
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(KubbModeCard.pressDuration);

    expect(
      tester.widget<AnimatedScale>(scaleFinder).scale,
      KubbModeCard.pressedScale,
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1);
  });

  testWidgets(
    'disabled state suppresses onTap, dims opacity and skips press scale',
    (tester) async {
      var taps = 0;
      await pump(
        tester,
        KubbModeCard(
          title: 'Tournament',
          subtitle: 'Bald verfuegbar',
          icon: LucideIcons.trophy,
          disabled: true,
          onTap: () => taps++,
        ),
      );

      // Opacity halved.
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(KubbModeCard),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.5);

      // IgnorePointer eats the tap — warnIfMissed: false because that is
      // exactly the assertion under test (the gesture intentionally misses).
      await tester.tap(find.byType(KubbModeCard), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(taps, 0);

      // Pressing a disabled card must not trigger scale-down.
      final scale = tester.widget<AnimatedScale>(
        find.descendant(
          of: find.byType(KubbModeCard),
          matching: find.byType(AnimatedScale),
        ),
      );
      expect(scale.scale, 1);
    },
  );

  testWidgets('renders accent stripe when accentTone is set', (tester) async {
    await pump(
      tester,
      KubbModeCard(
        title: 'Sniper',
        subtitle: '8 m',
        icon: LucideIcons.target,
        accentTone: KubbChipTone.sniperMeadow,
        onTap: () {},
      ),
    );

    final stripes = tester.widgetList<Container>(
      find.descendant(
        of: find.byType(KubbModeCard),
        matching: find.byType(Container),
      ),
    );

    final hasStripe = stripes.any(
      (c) => c.color == KubbTokens.meadow500,
    );
    expect(hasStripe, isTrue, reason: 'expected meadow500 accent stripe');
  });
}
