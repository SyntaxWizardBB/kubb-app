import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/bracket_canvas.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Golden suite for [BracketCanvas].
///
/// Goldens are generated in TASK-M2.3-T9 via
/// `flutter test --update-goldens test/features/tournament/presentation/bracket/bracket_canvas_golden_test.dart`.
/// Test slots are red until that task runs (and until the T1 widget stub is
/// merged into this branch — see briefing for the expected constructor).
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadAppFonts();
  });

  Future<void> pump(WidgetTester tester, Bracket bracket) async {
    await tester.pumpWidgetBuilder(
      BracketCanvas(bracket: bracket, editable: false),
      wrapper: materialAppWrapper(theme: KubbTheme.light()),
      surfaceSize: const Size(1280, 720),
    );
  }

  List<String> ids(int n) => [for (var i = 1; i <= n; i++) 'p$i'];

  group('BracketCanvas goldens', () {
    testGoldens('4-team bracket', (tester) async {
      await pump(tester, Bracket.singleElimination(ids(4)));
      await screenMatchesGolden(tester, 'bracket_canvas_4');
    });

    testGoldens('8-team bracket', (tester) async {
      await pump(tester, Bracket.singleElimination(ids(8)));
      await screenMatchesGolden(tester, 'bracket_canvas_8');
    });

    testGoldens('16-team bracket', (tester) async {
      await pump(tester, Bracket.singleElimination(ids(16)));
      await screenMatchesGolden(tester, 'bracket_canvas_16');
    });

    testGoldens('32-team bracket', (tester) async {
      await pump(tester, Bracket.singleElimination(ids(32)));
      await screenMatchesGolden(tester, 'bracket_canvas_32');
    });

    testGoldens('64-team bracket', (tester) async {
      await pump(tester, Bracket.singleElimination(ids(64)));
      await screenMatchesGolden(tester, 'bracket_canvas_64');
    });

    testGoldens('5-team bracket with BYE slots', (tester) async {
      await pump(tester, Bracket.singleElimination(ids(5)));
      await screenMatchesGolden(tester, 'bracket_canvas_bye_5');
    });

    testGoldens('4-team bracket with third-place playoff', (tester) async {
      await pump(
        tester,
        Bracket.singleElimination(ids(4), withThirdPlace: true),
      );
      await screenMatchesGolden(tester, 'bracket_canvas_third_place_4');
    });
  });
}
