import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Visual chip for one team-slot in the match config wizard.
/// Renders an avatar circle with the participant's initial, the
/// display name, and an "x" button to remove the slot from its team
/// (when [onRemove] is supplied).
class TeamSlotChip extends StatelessWidget {
  const TeamSlotChip({
    required this.label,
    required this.subtitle,
    required this.onRemove,
    this.isSelf = false,
    super.key,
  });

  final String label;
  final String subtitle;
  final VoidCallback? onRemove;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final initial =
        label.isEmpty ? '?' : label.characters.first.toUpperCase();
    final avatarColor =
        isSelf ? KubbTokens.meadow600 : KubbTokens.meadow400;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space2,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        border: Border.all(color: tokens.line),
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: avatarColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: tokens.fgMuted),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(LucideIcons.x, size: 16),
              tooltip: 'Entfernen',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
