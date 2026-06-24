import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/stage_type_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/presentation/stage_type_graph_builder_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

// W5-T02: the Ebene-2 canvas toggle is desktop-only and width-gated, exactly
// like the Ebene-1 StageGraphBuilderBody. Mobile platforms and narrow viewports
// must hide the form/canvas toggle and show the guided form editor only.
void main() {
  const matchFormat = StageTypeGraphBuilderController.defaultMatchFormat;

  StageTypeGraph koGraph() => StageTypeGraph(
        category: TypeStageCategory.ko,
        rounds: <TypeRound>[
          TypeRound(
            roundNumber: 1,
            fields: const <TypeField>[
              TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
              TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
            ],
            matchFormat: matchFormat,
            koMatchup: KoMatchup.seedHighVsLow,
          ),
          TypeRound(
            roundNumber: 2,
            fields: const <TypeField>[
              TypeField(id: 'R2F1', roundNumber: 2, slot: 1),
            ],
            matchFormat: matchFormat,
            koMatchup: KoMatchup.seedHighVsLow,
          ),
        ],
        edges: const <FieldEdge>[
          WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'),
          WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'),
        ],
      );

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
          stageTypeGraphBuilderProvider
              .overrideWith(() => StageTypeGraphBuilderController(koGraph())),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: StageTypeGraphBuilderBody()),
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
    expect(find.byType(StageTypeGraphBuilderBody), findsOneWidget);
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
