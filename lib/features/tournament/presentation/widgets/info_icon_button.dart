import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Small `info`-glyph button that opens a compact explainer dialog on tap.
///
/// Used next to selectable options in the stage-graph builder so every choice
/// (stage type, grouping strategy, edge seeding) carries a short, concrete
/// explanation of what it does to the matches. Keeps the 48dp touch target and
/// muted-glyph styling the rest of the tournament UI already uses.
class InfoIconButton extends StatelessWidget {
  const InfoIconButton({
    required this.title,
    required this.message,
    this.tooltip,
    super.key,
  });

  /// Dialog heading — the name of the option being explained.
  final String title;

  /// Explanation body shown in the dialog.
  final String message;

  /// Optional tooltip on the icon itself. Falls back to [title].
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return IconButton(
      icon: Icon(LucideIcons.info, size: 18, color: tokens.fgMuted),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: EdgeInsets.zero,
      tooltip: tooltip ?? title,
      onPressed: () => _show(context),
    );
  }

  Future<void> _show(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 128).clamp(220.0, 360.0);
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final tokens = Theme.of(ctx).extension<KubbTokens>()!;
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: width,
            child: Text(
              message,
              style: TextStyle(fontSize: 14, height: 1.4, color: tokens.fg),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
            ),
          ],
        );
      },
    );
  }
}
