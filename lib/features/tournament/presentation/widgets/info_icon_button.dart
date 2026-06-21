import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_bottom_sheet.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Project-wide info affordance: a small `info`-glyph that opens a compact
/// explainer in a bottom sheet on tap. Bottom sheet over dialog so the content
/// lands in thumb reach and dismisses with a swipe down — easier one-handed at
/// the pitch than a centred dialog with an OK button.
///
/// Used next to setup-wizard fields and stage-graph options so every choice
/// carries a short, concrete explanation. Keeps the 48dp touch target and the
/// muted-glyph styling the rest of the tournament UI uses.
///
/// For special cases (e.g. a richer explainer sheet) pass [onPressed] to route
/// the tap somewhere else while keeping the same glyph and placement.
class InfoIconButton extends StatelessWidget {
  const InfoIconButton({
    required this.title,
    required this.message,
    this.tooltip,
    this.onPressed,
    super.key,
  });

  /// Sheet heading — the name of the thing being explained.
  final String title;

  /// Explanation body shown in the sheet.
  final String message;

  /// Optional tooltip on the icon itself. Falls back to [title].
  final String? tooltip;

  /// Optional tap override. When set it replaces the default explainer sheet,
  /// so a caller can open its own sheet through the same affordance.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return IconButton(
      icon: Icon(LucideIcons.info, size: 18, color: tokens.fgMuted),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: EdgeInsets.zero,
      tooltip: tooltip ?? title,
      onPressed: onPressed ?? () => show(context),
    );
  }

  /// Opens the default explainer sheet. Exposed so a label tap (or another
  /// widget) can trigger the same sheet without going through the glyph.
  Future<void> show(BuildContext context) => showKubbBottomSheet<void>(
        context,
        header: _InfoSheetHeader(title: title),
        builder: (ctx) {
          final tokens = Theme.of(ctx).extension<KubbTokens>()!;
          return Padding(
            padding: const EdgeInsets.only(top: KubbTokens.space3),
            child: Text(
              message,
              style: TextStyle(fontSize: 14, height: 1.4, color: tokens.fg),
            ),
          );
        },
      );
}

class _InfoSheetHeader extends StatelessWidget {
  const _InfoSheetHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: tokens.fg,
        ),
      ),
    );
  }
}
