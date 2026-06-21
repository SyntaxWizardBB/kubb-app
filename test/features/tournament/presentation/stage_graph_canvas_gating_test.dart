import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/presentation/stage_graph_builder_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

// P4.1: the visual canvas editor toggle is desktop-only and width-gated.
// Mobile platforms and narrow viewports must hide the form/canvas toggle and
// show only the guided form editor.
void main() {
  StageGraph get0() => StageGraph(
        nodes: <StageNode>[
          StageNode(
            id: 'groups',
            type: StageNodeType.groupPhase,
            seeding: StageSeedingSource.asRouted,
            config: const <String, Object?>{'groupCount': 2, 'qualifierCount': 2},
          ),
        ],
        edges: const <StageEdge>[],
      );

  // NOTE: debugDefaultTargetPlatformOverride is a guarded foundation debug
  // variable; the test-invariant check runs BEFORE addTearDown callbacks, so it
  // must be reset inside the test body itself (see resetPlatform below).
  Future<void> pump(
    WidgetTester tester, {
    required TargetPlatform platform,
    required Size size,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stageGraphBuilderProvider
              .overrideWith(() => StageGraphBuilderController(get0(), 8)),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: StageGraphBuilderBody()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder toggle() => find.byWidgetPredicate((w) => w is SegmentedButton);
  void resetPlatform() => debugDefaultTargetPlatformOverride = null;

  testWidgets('desktop + wide viewport shows the canvas toggle', (tester) async {
    await pump(tester,
        platform: TargetPlatform.macOS, size: const Size(1000, 800));
    expect(toggle(), findsOneWidget);
    resetPlatform();
  });

  testWidgets('mobile hides the canvas toggle (form only)', (tester) async {
    await pump(tester,
        platform: TargetPlatform.android, size: const Size(1000, 800));
    expect(toggle(), findsNothing);
    expect(find.byType(StageGraphBuilderBody), findsOneWidget);
    resetPlatform();
  });

  testWidgets('desktop but narrow viewport hides the canvas toggle',
      (tester) async {
    await pump(tester,
        platform: TargetPlatform.macOS, size: const Size(420, 800));
    expect(toggle(), findsNothing);
    resetPlatform();
  });
}
