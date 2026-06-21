import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// Pill-style selectable chip used in the setup wizard.
///
/// One visual language for both selection kinds: a multi-select chip carries a
/// check glyph ([showCheck] true), a single-select chip none. Selected fills
/// `primary` with `onPrimary` text; unselected stays `bgRaised` with a `line`
/// border.
class KubbSelectChip extends StatelessWidget {
  const KubbSelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.showCheck = false,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Surfaces a leading check/circle glyph — used for multi-select sets so a
  /// chosen item reads as ticked rather than merely highlighted.
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final fg = selected ? tokens.onPrimary : tokens.fg;
    return InkWell(
      borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: KubbTokens.touchMin,
          minWidth: KubbTokens.touchMin,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space4,
          vertical: KubbTokens.space2,
        ),
        decoration: BoxDecoration(
          color: selected ? tokens.primary : tokens.bgRaised,
          borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
          border: Border.all(
            color: selected ? tokens.primary : tokens.line,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showCheck) ...[
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: KubbTokens.iconSm,
                color: selected ? tokens.onPrimary : tokens.fgMuted,
              ),
              const SizedBox(width: KubbTokens.space2),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
