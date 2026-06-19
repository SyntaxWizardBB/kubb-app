import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Whether the running platform can host the visual drag-and-drop DAG **canvas**
/// editor (ADR-0033 P4): desktop only — macOS / Windows / Linux. Mobile
/// (iOS / Android) falls back to the guided form editor. Web is treated as
/// canvas-capable (typically a desktop browser); the width breakpoint
/// [kCanvasMinWidth] additionally gates narrow viewports there.
///
/// Uses [defaultTargetPlatform] (not `dart:io`'s `Platform`, which throws on
/// web) so it stays web-safe and is overridable in widget tests via
/// `debugDefaultTargetPlatformOverride`.
bool get isCanvasCapablePlatform {
  if (kIsWeb) return true;
  switch (defaultTargetPlatform) {
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return true;
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return false;
  }
}

/// Minimum logical width at which the canvas editor is offered. Below this the
/// guided form editor is used even on a canvas-capable platform (e.g. a narrow
/// desktop window).
const double kCanvasMinWidth = 720;

/// Whether the canvas editor should be available given the platform AND the
/// current viewport [width].
bool isCanvasAvailable(double width) =>
    isCanvasCapablePlatform && width >= kCanvasMinWidth;
