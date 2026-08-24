import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/breakpoints.dart';

void main() {
  group('KubbBreakpoint.fromWidth', () {
    test('classifies the three bands by their design-system thresholds', () {
      expect(KubbBreakpoint.fromWidth(0), KubbBreakpoint.compact);
      expect(KubbBreakpoint.fromWidth(719), KubbBreakpoint.compact);
      expect(KubbBreakpoint.fromWidth(720), KubbBreakpoint.medium);
      expect(KubbBreakpoint.fromWidth(1079), KubbBreakpoint.medium);
      expect(KubbBreakpoint.fromWidth(1080), KubbBreakpoint.expanded);
    });

    test('a phone stays compact and a desktop window expanded', () {
      expect(KubbBreakpoint.fromWidth(390).isCompact, isTrue);
      expect(KubbBreakpoint.fromWidth(390).isWide, isFalse);
      expect(KubbBreakpoint.fromWidth(1440).isExpanded, isTrue);
      expect(KubbBreakpoint.fromWidth(1440).isWide, isTrue);
    });

    test('only compact reads full-bleed; the wider bands cap the column', () {
      expect(KubbBreakpoint.compact.contentMaxWidth, double.infinity);
      expect(KubbBreakpoint.medium.contentMaxWidth, 720);
      expect(KubbBreakpoint.expanded.contentMaxWidth, 1080);
    });
  });

  group('KubbResponsive', () {
    Future<void> pumpAt(WidgetTester tester, double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: width,
              height: 200,
              child: KubbResponsive(
                builder: (context, breakpoint) => Text(breakpoint.name),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('reads the class off the incoming constraints', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpAt(tester, 400);
      expect(find.text('compact'), findsOneWidget,
          reason: 'a narrow pane is compact even on a wide window');

      await pumpAt(tester, 900);
      expect(find.text('medium'), findsOneWidget);

      await pumpAt(tester, 1400);
      expect(find.text('expanded'), findsOneWidget);
    });
  });

  group('responsiveValue', () {
    testWidgets('falls back to the next narrower value when one is missing',
        (tester) async {
      late String seen;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1400, 800)),
          child: Builder(
            builder: (context) {
              seen = responsiveValue(context, compact: 'c', medium: 'm');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(seen, 'm');
    });
  });
}
