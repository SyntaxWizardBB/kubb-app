import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

class TournierCard extends StatelessWidget {
  const TournierCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const fg = KubbTokens.chalk50;
    final muted = fg.withValues(alpha: 0.85);
    return Material(
      color: KubbTokens.wood500,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 120),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        eyebrow.toUpperCase(),
                        style: t.labelSmall?.copyWith(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          letterSpacing: 0.88, color: muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        style: t.headlineMedium?.copyWith(
                          fontSize: 28, fontWeight: FontWeight.w800,
                          letterSpacing: -0.56, height: 1, color: fg,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle, style: t.bodyMedium?.copyWith(fontSize: 13, color: muted)),
                    ],
                  ),
                ),
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
                  ),
                  child: const Center(child: KubbIcon(KubbIcons.cup, color: fg, size: 32)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
