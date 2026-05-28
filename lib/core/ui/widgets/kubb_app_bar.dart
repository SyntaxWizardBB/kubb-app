import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Central AppBar for Kubb screens.
///
/// Mirrors the `BK.AppBar` block from `docs/design/ui_kits/app/shared.jsx`:
/// padding `54 / 12 / 6` (top includes safe-area), eyebrow (11px upper) above
/// the title (18px bold), back/leading slot 48dp left, optional 48dp slot
/// right. Background is `KubbTokens.bg`.
///
/// Two construction forms are supported:
///
/// * The default constructor takes string `title` / `eyebrow` plus optional
///   widget slots and renders the brand typography internally. This is the
///   legacy entry point used by most screens.
/// * `KubbAppBar.slots` exposes raw widget slots (`leading`, `eyebrow`,
///   `title`, `trailing`) for screens that need custom content in the
///   eyebrow- or title-line (e.g. tabs, badges, brand mark).
class KubbAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Legacy / convenience constructor. Renders [title] + optional [eyebrow]
  /// in the brand typography.
  ///
  /// For the right-side slot, prefer the Material-style [actions] list — it
  /// renders as a right-aligned [Row] so screens can stack multiple icon
  /// buttons. The single-widget [trailing] slot is the lower-level escape
  /// hatch (custom layout, badges, etc.) and wins over [actions] when both
  /// are supplied.
  const KubbAppBar({
    required String title,
    super.key,
    String? eyebrow,
    this.leading,
    List<Widget>? actions,
    Widget? trailing,
    this.automaticallyImplyLeading = true,
  })  : _titleSlot = null,
        _eyebrowSlot = null,
        _titleText = title,
        _eyebrowText = eyebrow,
        _actions = actions,
        _trailing = trailing;

  /// Slot-based constructor following the mobile-kit `BK.AppBar` contract.
  /// All slots are optional widgets, except [title] which is required and
  /// expected to render the screen name in display typography.
  const KubbAppBar.slots({
    required Widget title,
    super.key,
    Widget? eyebrow,
    this.leading,
    Widget? trailing,
    this.automaticallyImplyLeading = true,
  })  : _titleSlot = title,
        _eyebrowSlot = eyebrow,
        _titleText = null,
        _eyebrowText = null,
        _actions = null,
        _trailing = trailing;

  /// Left-side slot. Defaults to a back-button when the route can pop and
  /// [automaticallyImplyLeading] is true; otherwise a 48dp spacer.
  final Widget? leading;

  /// When true, falls back to a `context.pop`-wired back-button if no
  /// [leading] is supplied and the navigator can pop.
  final bool automaticallyImplyLeading;

  // Slot-mode payloads (set only via `.slots` constructor).
  final Widget? _titleSlot;
  final Widget? _eyebrowSlot;

  // Text-mode payloads (set only via the default constructor).
  final String? _titleText;
  final String? _eyebrowText;

  // Right-side slots. Either a Material-style list of icon buttons, or a
  // single trailing widget. `_trailing` takes precedence when both are set.
  final List<Widget>? _actions;
  final Widget? _trailing;

  /// Spec target for the top padding (incl. status-bar inset) from
  /// `shared.jsx` BK.AppBar (`padding: 54px 12px 6px`). On notch devices the
  /// 44dp inset eats most of it, leaving ~10dp visual gap below the cutout;
  /// on inset-free surfaces the full 54dp keeps the eyebrow off the edge.
  static const double _specTop = 54;

  /// Fixed height claimed in the Scaffold layout: spec-top (54) + 48dp
  /// leading/trailing slot (matches the centered eyebrow+title column) +
  /// spec-bottom (6) = 108.
  @override
  Size get preferredSize => const Size.fromHeight(108);

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    final canPop = automaticallyImplyLeading && Navigator.of(context).canPop();
    final leadingWidget = leading ??
        (canPop
            ? IconButton(
                icon: const Icon(LucideIcons.arrowLeft),
                color: tokens.fg,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                iconSize: 24,
                splashRadius: 24,
                constraints: const BoxConstraints.tightFor(
                  width: KubbTokens.touchMin,
                  height: KubbTokens.touchMin,
                ),
                onPressed: () => context.pop(),
              )
            : const SizedBox(width: KubbTokens.touchMin));

    final eyebrowWidget = _eyebrowSlot ?? _buildEyebrowText(textTheme, tokens);
    final titleWidget = _titleSlot ?? _buildTitleText(textTheme, tokens);
    final actions = _actions;
    final trailingWidget = _trailing ??
        (actions != null && actions.isNotEmpty
            ? Row(mainAxisSize: MainAxisSize.min, children: actions)
            : null);

    return Material(
      color: tokens.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KubbTokens.space3,
          _specTop,
          KubbTokens.space3,
          KubbTokens.space1half,
        ),
        child: Row(
          children: [
            leadingWidget,
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?eyebrowWidget,
                  titleWidget,
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: KubbTokens.touchMin),
              child: Align(
                alignment: Alignment.centerRight,
                child: trailingWidget ?? const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildEyebrowText(TextTheme textTheme, KubbTokens tokens) {
    final text = _eyebrowText;
    if (text == null || text.isEmpty) return null;
    return Text(
      text.toUpperCase(),
      style: textTheme.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.88,
        color: tokens.fgMuted,
      ),
    );
  }

  Widget _buildTitleText(TextTheme textTheme, KubbTokens tokens) {
    return Text(
      _titleText ?? '',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.36,
        color: tokens.fg,
      ),
    );
  }
}
