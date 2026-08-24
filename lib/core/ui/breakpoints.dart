import 'package:flutter/widgets.dart';

/// Viewport size classes. The thresholds are the design system's own layout
/// maxes (`--kc-container-narrow` 720, `--kc-container` 1080), so a layout
/// that switches here lines up with the widths the design was drawn against.
///
/// [KubbBreakpoint.compact] is the phone layout the app shipped with; the two
/// wider classes are what the desktop surfaces branch on.
enum KubbBreakpoint {
  compact,
  medium,
  expanded;

  static const double mediumMinWidth = 720;
  static const double expandedMinWidth = 1080;

  static KubbBreakpoint fromWidth(double width) {
    if (width >= expandedMinWidth) return KubbBreakpoint.expanded;
    if (width >= mediumMinWidth) return KubbBreakpoint.medium;
    return KubbBreakpoint.compact;
  }

  /// The size class of the window. Use [KubbResponsive] instead when the
  /// widget sits in a pane that is narrower than the window — that reads the
  /// incoming constraints rather than the screen.
  static KubbBreakpoint of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  bool get isCompact => this == KubbBreakpoint.compact;

  /// True from tablet width up: the point where a two-pane or sidebar layout
  /// starts to pay off.
  bool get isWide => this != KubbBreakpoint.compact;

  bool get isExpanded => this == KubbBreakpoint.expanded;

  /// Content width cap for centred reading columns. Full-bleed surfaces (the
  /// admin dashboard, the bracket canvas) ignore this and take the viewport.
  double get contentMaxWidth => switch (this) {
        KubbBreakpoint.compact => double.infinity,
        KubbBreakpoint.medium => 720,
        KubbBreakpoint.expanded => 1080,
      };
}

/// Resolves the size class from the **incoming constraints** rather than the
/// window, so it stays correct inside a pane that is narrower than the screen.
/// Use it for layout branching; use [KubbBreakpoint.of] when the window itself
/// is the right question.
///
/// This is a thin [LayoutBuilder]: the builder runs on every layout pass, not
/// only when the class changes. That is fine for choosing a layout — if a
/// subtree is expensive, hoist it into a `const` or a cached field yourself.
class KubbResponsive extends StatelessWidget {
  const KubbResponsive({required this.builder, super.key});

  final Widget Function(BuildContext context, KubbBreakpoint breakpoint)
      builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) =>
            builder(context, KubbBreakpoint.fromWidth(constraints.maxWidth)),
      );
}

/// Picks one of three values by size class, falling back to the next narrower
/// one when a wider value is not given. Keeps per-widget branching to a single
/// expression instead of a switch in every build method.
T responsiveValue<T>(
  BuildContext context, {
  required T compact,
  T? medium,
  T? expanded,
}) {
  final breakpoint = KubbBreakpoint.of(context);
  return switch (breakpoint) {
    KubbBreakpoint.compact => compact,
    KubbBreakpoint.medium => medium ?? compact,
    KubbBreakpoint.expanded => expanded ?? medium ?? compact,
  };
}
