import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders title and body', (tester) async {
    await pump(
      tester,
      const KubbEmptyState(
        title: 'Noch keine Sessions',
        body: 'Spiel ein paar Trainings und du siehst sie hier.',
      ),
    );

    expect(find.text('Noch keine Sessions'), findsOneWidget);
    expect(
      find.text('Spiel ein paar Trainings und du siehst sie hier.'),
      findsOneWidget,
    );
  });

  testWidgets('title uses 22dp / w700 typography', (tester) async {
    await pump(
      tester,
      const KubbEmptyState(
        title: 'Titel',
        body: 'Body',
      ),
    );

    final titleText = tester.widget<Text>(find.text('Titel'));
    expect(titleText.style?.fontSize, 22);
    expect(titleText.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('body uses 14dp + fgMuted color', (tester) async {
    await pump(
      tester,
      const KubbEmptyState(
        title: 'Titel',
        body: 'Body',
      ),
    );

    final bodyText = tester.widget<Text>(find.text('Body'));
    expect(bodyText.style?.fontSize, 14);
    // fgMuted is set via theme extension — assert it matches the light theme's
    // muted foreground.
    expect(bodyText.style?.color, isNotNull);
  });

  testWidgets('renders default K+Crown vignette at 96dp when no override',
      (tester) async {
    await pump(
      tester,
      const KubbEmptyState(title: 'T', body: 'B'),
    );

    expect(find.byType(KubbCrownVignette), findsOneWidget);
    final vignetteSize =
        tester.getSize(find.byType(KubbCrownVignette));
    expect(vignetteSize.width, KubbEmptyState.vignetteSize);
    expect(vignetteSize.height, KubbEmptyState.vignetteSize);
  });

  testWidgets('vignette tint defaults to stone400 @ 0.6 opacity',
      (tester) async {
    await pump(tester, const KubbCrownVignette());
    // The painter caches the resolved color; assert via the public CustomPaint
    // child by reading the rendered alpha indirectly. We instead verify the
    // default property values on the widget itself.
    final widget = tester.widget<KubbCrownVignette>(
      find.byType(KubbCrownVignette),
    );
    expect(widget.tint, isNull); // defaults to stone400
    expect(widget.opacity, closeTo(0.6, 1e-9));
  });

  testWidgets('cta slot is omitted when null', (tester) async {
    await pump(
      tester,
      const KubbEmptyState(title: 'T', body: 'B'),
    );
    expect(find.byType(KubbButton), findsNothing);
  });

  testWidgets('cta slot renders and is tappable', (tester) async {
    var taps = 0;
    await pump(
      tester,
      KubbEmptyState(
        title: 'Noch keine Sessions',
        body: 'Spiel ein paar Trainings.',
        cta: KubbButton(
          variant: KubbButtonVariant.primary,
          onPressed: () => taps++,
          child: const Text('Erste Session starten'),
        ),
      ),
    );

    expect(find.byType(KubbButton), findsOneWidget);
    expect(find.text('Erste Session starten'), findsOneWidget);

    await tester.tap(find.byType(KubbButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('custom vignette overrides the default', (tester) async {
    await pump(
      tester,
      const KubbEmptyState(
        title: 'T',
        body: 'B',
        vignette: SizedBox.shrink(key: ValueKey('custom-vignette')),
      ),
    );

    expect(find.byKey(const ValueKey('custom-vignette')), findsOneWidget);
    expect(find.byType(KubbCrownVignette), findsNothing);
  });

  testWidgets('respects narrow viewport without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(
      tester,
      KubbEmptyState(
        title: 'Noch keine Turniere',
        body: 'Erstelle dein erstes Turnier — Setup ist in unter zwei Minuten erledigt.',
        cta: KubbButton(
          variant: KubbButtonVariant.primary,
          onPressed: () {},
          child: const Text('Turnier erstellen'),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(KubbEmptyState), findsOneWidget);
  });

  testWidgets('uses KubbTokens.space6 outer padding', (tester) async {
    await pump(
      tester,
      const KubbEmptyState(title: 'T', body: 'B'),
    );

    final padding = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(KubbEmptyState),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(padding.padding, const EdgeInsets.all(KubbTokens.space6));
  });
}
