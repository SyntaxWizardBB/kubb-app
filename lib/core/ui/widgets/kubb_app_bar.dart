import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Central AppBar for Kubb screens.
///
/// Follows the M3 top-app-bar layout: the real status-bar inset followed by a
/// fixed content band ([_toolbarHeight]) that vertically centres the eyebrow
/// (11px upper) above the title (18px bold), with a 48dp leading slot left and
/// an optional 48dp slot right. Background is `KubbTokens.bg`.
///
/// Replaces the old fixed 54dp top padding lifted verbatim from the React
/// mock-up (`shared.jsx` `padding: 54px 12px 6px`), which ignored the device
/// status-bar height and left an oversized gap below it on most phones.
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

  /// M3 content band below the status bar. The 48dp leading/trailing slots and
  /// the eyebrow+title column are vertically centred inside it. The status-bar
  /// inset is added on top (see [preferredSize] / [build]).
  static const double _toolbarHeight = 64;

  /// Raw status-bar inset resolved without a [BuildContext] so [preferredSize]
  /// agrees with the `MediaQuery.paddingOf(context).top` used in [build].
  /// Falls back to 0 when no view is attached (e.g. some test harnesses).
  static double get _statusBarInset {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return 0;
    final view = views.first;
    return view.padding.top / view.devicePixelRatio;
  }

  /// Status-bar inset + the fixed content band, so the bar hugs the status bar
  /// (M3) instead of claiming a hard-coded 108dp regardless of the device.
  @override
  Size get preferredSize => Size.fromHeight(_statusBarInset + _toolbarHeight);

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
        // Push content below the real status bar (M3), then host it in a
        // fixed-height band so the 48dp slots and the eyebrow+title column sit
        // vertically centred — no oversized fixed top gap on short status bars.
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: SizedBox(
          height: _toolbarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space3),
            // Stack instead of a Row so the eyebrow+title stay centred on the
            // *screen*, not merely within the space left over by the side
            // slots. A Row(Expanded) recentres the title whenever the leading
            // and trailing slots differ in width (e.g. a 48dp back-button on
            // the left vs. a filter+inbox action row on the right), which made
            // titles drift off-centre. The symmetric horizontal padding below
            // reserves room for the side slots so a centred title clears them.
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KubbTokens.touchMin + KubbTokens.space2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ?eyebrowWidget,
                      titleWidget,
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: leadingWidget,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(minWidth: KubbTokens.touchMin),
                    child: trailingWidget ?? const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildEyebrowText(TextTheme textTheme, KubbTokens tokens) {
    final text = _eyebrowText;
    if (text == null || text.isEmpty) return null;
    return Text(
      text.toUpperCase(),
      textAlign: TextAlign.center,
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
      textAlign: TextAlign.center,
      style: textTheme.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.36,
        color: tokens.fg,
      ),
    );
  }
}
