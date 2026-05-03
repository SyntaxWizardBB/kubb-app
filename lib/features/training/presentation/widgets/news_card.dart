import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

class NewsCard extends StatelessWidget {
  const NewsCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final t = Theme.of(context).textTheme;
    return Material(
      color: tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async => onTap(),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: tokens.line),
            borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
          ),
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                        fontSize: 11, fontWeight: FontWeight.w600,
                        letterSpacing: 0.88, color: KubbTokens.meadow600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: t.titleSmall?.copyWith(
                        fontSize: 15, fontWeight: FontWeight.w700,
                        letterSpacing: -0.15, height: 1.2, color: tokens.fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: t.bodySmall?.copyWith(fontSize: 12, color: tokens.fgMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              KubbIcon(LucideIcons.chevronRight, color: tokens.fgMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
