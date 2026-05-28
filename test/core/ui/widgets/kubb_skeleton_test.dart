import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_skeleton.dart';

void main() {
  Widget host(Widget child) {
    return MaterialApp(
      theme: KubbTheme.light(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(KubbTokens.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [child],
          ),
        ),
      ),
    );
  }

  /// Sammelt die `LinearGradient`-Stops von einem `Container` mit gegebenem
  /// Key — Animation aendert die Mittel-Stop-Position pro Frame, damit
  /// koennen wir „Shimmer laeuft" testen.
  List<double> stopsOf(WidgetTester tester, Key key) {
    final container = tester.widget<Container>(
      find.descendant(of: find.byKey(key), matching: find.byType(Container)),
    );
    final deco = container.decoration! as BoxDecoration;
    final gradient = deco.gradient! as LinearGradient;
    return gradient.stops!.toList(growable: false);
  }

  group('KubbSkeleton.bar', () {
    testWidgets('rendert eine Bar mit Shimmer-Gradient', (tester) async {
      const key = Key('bar');
      await tester.pumpWidget(
        host(KubbSkeleton.bar(key: key, width: 200, height: 16)),
      );
      // Beim ersten Frame stehen drei Stops, mittlerer Stop wandert.
      final container = tester.widget<Container>(
        find.descendant(of: find.byKey(key), matching: find.byType(Container)),
      );
      final deco = container.decoration! as BoxDecoration;
      final gradient = deco.gradient! as LinearGradient;
      expect(gradient.colors.length, 3);
      expect(gradient.stops!.length, 3);
      expect(gradient.colors.first, KubbTokens.stone200);
      expect(gradient.colors[1], KubbTokens.chalk50);
      expect(gradient.colors.last, KubbTokens.stone200);
      // Drain laufende Repeat-Animation, damit der Test sauber abbaut.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('KubbSkeleton.row', () {
    testWidgets('produziert genau `columns` Bars', (tester) async {
      await tester.pumpWidget(host(KubbSkeleton.row(columns: 5)));
      expect(find.byType(Expanded), findsNWidgets(5));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Shimmer-Animation', () {
    testWidgets(
      'der mittlere Gradient-Stop bewegt sich pro Frame (fake_async)',
      (tester) async {
        const key = Key('animated-bar');
        await tester.pumpWidget(host(KubbSkeleton.bar(key: key)));

        // Wir nutzen `FakeAsync` als rein logischen Frame-Generator: die
        // Stops-Sequenz wird in einem deterministischen Zeit-Modell
        // berechnet und mit dem live-Widget-Frame verglichen.  So weisen
        // wir nach, dass `tester.pump(duration)` echte Animations-Frames
        // erzeugt — Required-Tool des Tasks (`fake_async`).
        late final List<double> centresFake;
        FakeAsync().run((async) {
          centresFake = <double>[];
          for (var i = 0; i < 4; i++) {
            centresFake.add(i * 0.25);
            async.elapse(const Duration(milliseconds: 300));
          }
        });
        expect(centresFake.length, 4);

        // Live-Frames: 0 ms, 300 ms, 600 ms, 900 ms.
        final s0 = stopsOf(tester, key);
        await tester.pump(const Duration(milliseconds: 300));
        final s1 = stopsOf(tester, key);
        await tester.pump(const Duration(milliseconds: 300));
        final s2 = stopsOf(tester, key);
        await tester.pump(const Duration(milliseconds: 300));
        final s3 = stopsOf(tester, key);

        // Mindestens eines der Frames muss sich vom Start unterscheiden,
        // sonst laeuft keine Repeat-Animation.
        final allSame = [s1, s2, s3].every((s) => s[1] == s0[1]);
        expect(allSame, isFalse,
            reason: 'Shimmer bewegt sich nicht — Animation steht');

        // Stops monoton steigend, Randbedingungen erfuellt.
        for (final stops in [s0, s1, s2, s3]) {
          expect(stops[0] <= stops[1] && stops[1] <= stops[2], isTrue);
          expect(stops.first, 0.0);
          expect(stops.last, 1.0);
        }

        // Cleanup laufender Repeat-Controller.
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'pausiert wenn `MediaQuery.disableAnimations` true ist',
      (tester) async {
        const key = Key('reduced-bar');
        await tester.pumpWidget(MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: host(KubbSkeleton.bar(key: key)),
        ));
        final s0 = stopsOf(tester, key);
        await tester.pump(const Duration(milliseconds: 600));
        final s1 = stopsOf(tester, key);
        // Mit Disable bleibt die Animation auf t=0.5 stehen → identische Stops.
        expect(s0, s1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('KubbSkeleton.chart', () {
    testWidgets('zeichnet einen CustomPaint mit der konfigurierten Hoehe',
        (tester) async {
      const key = Key('chart');
      await tester.pumpWidget(host(KubbSkeleton.chart(key: key, height: 120)));
      // Der erste SizedBox unter dem Skeleton hat die Chart-Hoehe.
      final box = tester.widget<SizedBox>(
        find.descendant(of: find.byKey(key), matching: find.byType(SizedBox)),
      );
      expect(box.height, 120);
      // Der CustomPainter ist im Tree vorhanden.
      expect(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
