import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// Visual variant der Brand-Buttons.
///
/// Quelle: `docs/design/preview/components-buttons.html` und
/// `docs/design/quality-gates/component-library.md` (Buttons, Sprint-B).
enum KubbButtonVariant {
  /// Primary action — gefuellt mit meadow-600 (= `--kc-hit`).
  primary,

  /// Secondary action — stone-200-Surface, Vordergrund [KubbTokens.fg].
  secondary,

  /// Ghost — transparent, nur Text/Icon in [KubbTokens.fg].
  ghost,

  /// Destructive — gefuellt mit `--kc-miss`, Foreground [KubbTokens.onDanger].
  danger,
}

/// Groessen-Stufen.
///
/// Min-Heights bewusst groesser als HTML-Preview, da Touch-Targets auf mobilen
/// Endgeraeten Pflicht sind (`KubbTokens.touchMin = 48`).
enum KubbButtonSize {
  /// Compact 40 dp — fuer dichte Dialog-Footer.
  small,

  /// Default 48 dp — Standard auf allen Screens.
  medium,

  /// FAB-Aequivalent 64 dp — Home-Action, Wizard-CTA.
  large,
}

/// Brand-Button — Wrapper um Material-`InkWell`/`Material` mit
/// vier Variants ([KubbButtonVariant]) und drei Groessen ([KubbButtonSize]).
///
/// Zustaende:
/// - **enabled** wenn [onPressed] gesetzt ist.
/// - **disabled** wenn [onPressed] `null` ist — Opacity 40 %.
/// - **loading** wenn [isLoading] gesetzt ist — Label wird durch
///   `CircularProgressIndicator` ersetzt und Taps unterdrueckt.
class KubbButton extends StatelessWidget {
  const KubbButton({
    required this.variant,
    required this.child,
    super.key,
    this.size = KubbButtonSize.medium,
    this.onPressed,
    this.isLoading = false,
  });

  final KubbButtonVariant variant;
  final KubbButtonSize size;
  final VoidCallback? onPressed;
  final Widget child;
  final bool isLoading;

  /// Min-Heights pro [KubbButtonSize] (siehe Doc-Kommentar oben).
  static const double minHeightSmall = 40;
  static const double minHeightMedium = 48;
  static const double minHeightLarge = 64;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final palette = _resolvePalette(tokens);
    final metrics = _resolveMetrics();

    final enabled = onPressed != null && !isLoading;

    final labelStyle = TextStyle(
      color: palette.foreground,
      fontSize: metrics.fontSize,
      fontWeight: FontWeight.w700,
      height: 1.1,
      letterSpacing: -0.1,
    );

    final content = isLoading
        ? SizedBox(
            height: metrics.fontSize + 4,
            width: metrics.fontSize + 4,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(palette.foreground),
            ),
          )
        : DefaultTextStyle.merge(
            style: labelStyle,
            child: IconTheme.merge(
              data: IconThemeData(color: palette.foreground, size: metrics.iconSize),
              child: child,
            ),
          );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: palette.background,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          splashColor: palette.foreground.withValues(alpha: 0.12),
          highlightColor: palette.foreground.withValues(alpha: 0.06),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: metrics.minHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
              child: Center(
                widthFactor: 1,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  _ButtonPalette _resolvePalette(KubbTokens tokens) {
    switch (variant) {
      case KubbButtonVariant.primary:
        return _ButtonPalette(
          background: KubbTokens.meadow600,
          foreground: tokens.onPrimary,
        );
      case KubbButtonVariant.secondary:
        return _ButtonPalette(
          background: KubbTokens.stone200,
          foreground: tokens.fg,
        );
      case KubbButtonVariant.ghost:
        return _ButtonPalette(
          background: Colors.transparent,
          foreground: tokens.fg,
        );
      case KubbButtonVariant.danger:
        return _ButtonPalette(
          background: KubbTokens.miss,
          foreground: tokens.onDanger,
        );
    }
  }

  _ButtonMetrics _resolveMetrics() {
    switch (size) {
      case KubbButtonSize.small:
        return const _ButtonMetrics(
          minHeight: minHeightSmall,
          horizontalPadding: 14,
          fontSize: 13,
          iconSize: 16,
        );
      case KubbButtonSize.medium:
        return const _ButtonMetrics(
          minHeight: minHeightMedium,
          horizontalPadding: 18,
          fontSize: 15,
          iconSize: 18,
        );
      case KubbButtonSize.large:
        return const _ButtonMetrics(
          minHeight: minHeightLarge,
          horizontalPadding: 22,
          fontSize: 17,
          iconSize: 22,
        );
    }
  }
}

class _ButtonPalette {
  const _ButtonPalette({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}

class _ButtonMetrics {
  const _ButtonMetrics({
    required this.minHeight,
    required this.horizontalPadding,
    required this.fontSize,
    required this.iconSize,
  });

  final double minHeight;
  final double horizontalPadding;
  final double fontSize;
  final double iconSize;
}
