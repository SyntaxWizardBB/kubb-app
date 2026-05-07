import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

class KubbAppBar extends StatelessWidget implements PreferredSizeWidget {
  const KubbAppBar({
    required this.title,
    super.key,
    this.eyebrow,
    this.leading,
    this.actions,
    this.automaticallyImplyLeading = true,
  });

  final String title;
  final String? eyebrow;
  final Widget? leading;
  final Widget? actions;
  final bool automaticallyImplyLeading;

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

    final eyebrowText = eyebrow;
    return Material(
      color: tokens.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KubbTokens.space3, KubbTokens.space6, KubbTokens.space3, KubbTokens.space2,
        ),
        child: Row(
          children: [
            leadingWidget,
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (eyebrowText != null && eyebrowText.isNotEmpty)
                    Text(
                      eyebrowText.toUpperCase(),
                      style: textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.88,
                        color: tokens.fgMuted,
                      ),
                    ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.36,
                      color: tokens.fg,
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: KubbTokens.touchMin),
              child: Align(
                alignment: Alignment.centerRight,
                child: _buildTrailing(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrailing() {
    return actions ?? const SizedBox.shrink();
  }
}
