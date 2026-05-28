import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool settle = true,
  }) async {
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Material findInnerMaterial(WidgetTester tester) {
    return tester.widget<Material>(
      find.descendant(of: find.byType(KubbButton), matching: find.byType(Material)).first,
    );
  }

  group('variants render expected palette', () {
    testWidgets('primary uses meadow-600 background', (tester) async {
      await pump(
        tester,
        KubbButton(
          variant: KubbButtonVariant.primary,
          onPressed: () {},
          child: const Text('Speichern'),
        ),
      );
      expect(find.text('Speichern'), findsOneWidget);
      expect(findInnerMaterial(tester).color, KubbTokens.meadow600);
    });

    testWidgets('secondary uses stone-200 surface', (tester) async {
      await pump(
        tester,
        KubbButton(
          variant: KubbButtonVariant.secondary,
          onPressed: () {},
          child: const Text('Abbrechen'),
        ),
      );
      expect(findInnerMaterial(tester).color, KubbTokens.stone200);
    });

    testWidgets('ghost is transparent', (tester) async {
      await pump(
        tester,
        KubbButton(
          variant: KubbButtonVariant.ghost,
          onPressed: () {},
          child: const Text('Mehr'),
        ),
      );
      expect(findInnerMaterial(tester).color, Colors.transparent);
    });

    testWidgets('danger uses miss tone', (tester) async {
      await pump(
        tester,
        KubbButton(
          variant: KubbButtonVariant.danger,
          onPressed: () {},
          child: const Text('Verwerfen'),
        ),
      );
      expect(findInnerMaterial(tester).color, KubbTokens.miss);
    });
  });

  group('sizes', () {
    testWidgets('small respects 40dp min-height', (tester) async {
      await pump(
        tester,
        KubbButton(
          variant: KubbButtonVariant.primary,
          size: KubbButtonSize.small,
          onPressed: () {},
          child: const Text('S'),
        ),
      );
      final size = tester.getSize(find.byType(KubbButton));
      expect(size.height, KubbButton.minHeightSmall);
    });

    testWidgets('medium respects 48dp min-height (default)', (tester) async {
      await pump(
        tester,
        KubbButton(
          variant: KubbButtonVariant.primary,
          onPressed: () {},
          child: const Text('M'),
        ),
      );
      expect(
        tester.getSize(find.byType(KubbButton)).height,
        KubbButton.minHeightMedium,
      );
    });

    testWidgets('large respects 64dp min-height', (tester) async {
      await pump(
        tester,
        KubbButton(
          variant: KubbButtonVariant.primary,
          size: KubbButtonSize.large,
          onPressed: () {},
          child: const Text('L'),
        ),
      );
      expect(
        tester.getSize(find.byType(KubbButton)).height,
        KubbButton.minHeightLarge,
      );
    });
  });

  group('states', () {
    testWidgets('enabled fires onPressed', (tester) async {
      var taps = 0;
      await pump(
        tester,
        KubbButton(
          variant: KubbButtonVariant.primary,
          onPressed: () => taps++,
          child: const Text('Tap'),
        ),
      );
      await tester.tap(find.byType(KubbButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('disabled (onPressed null) renders at 40% opacity and absorbs taps',
        (tester) async {
      await pump(
        tester,
        const KubbButton(
          variant: KubbButtonVariant.primary,
          child: Text('Disabled'),
        ),
      );

      final opacity = tester.widget<Opacity>(
        find.descendant(of: find.byType(KubbButton), matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, closeTo(0.4, 1e-9));

      final inkWell = tester.widget<InkWell>(
        find.descendant(of: find.byType(KubbButton), matching: find.byType(InkWell)).first,
      );
      expect(inkWell.onTap, isNull);
    });

    testWidgets('loading replaces child with CircularProgressIndicator and blocks taps',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        KubbButton(
          variant: KubbButtonVariant.primary,
          isLoading: true,
          onPressed: () => taps++,
          child: const Text('Speichert'),
        ),
        settle: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Speichert'), findsNothing);

      await tester.tap(find.byType(KubbButton));
      await tester.pump();
      expect(taps, 0);
    });
  });
}
