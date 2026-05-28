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
  /// in the brand typography. Either [actions] or [trailing] can be supplied
  /// for the right-side icon slot; [trailing] wins when both are set.
  const KubbAppBar({
    required String title,
    super.key,
    String? eyebrow,
    this.leading,
    Widget? actions,
    Widget? trailing,
    this.automaticallyImplyLeading = true,
  })  : _titleSlot = null,
        _eyebrowSlot = null,
        _titleText = title,
        _eyebrowText = eyebrow,
        _trailing = trailing ?? actions;

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

  // Right-side slot, normalised across both constructors.
  final Widget? _trailing;

  @override
  Size get preferredSize => const Size.fromHeight(88);

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

    return Material(
      color: tokens.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KubbTokens.space3,
          KubbTokens.space6,
          KubbTokens.space3,
          KubbTokens.space2,
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
                child: _trailing ?? const SizedBox.shrink(),
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
