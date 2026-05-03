import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';

class RecentSection extends StatelessWidget {
  const RecentSection({required this.title, required this.items, super.key});

  final String title;
  final List<RecentSessionView> items;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: t.labelSmall?.copyWith(
            fontSize: 11, fontWeight: FontWeight.w600,
            letterSpacing: 0.88, color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Container(
          decoration: BoxDecoration(
            color: tokens.bgRaised,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space3),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++)
                _RecentRow(item: items[i], showDivider: i < items.length - 1),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.item, required this.showDivider});

  final RecentSessionView item;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        border: showDivider ? Border(bottom: BorderSide(color: tokens.line)) : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              item.modeTag.toUpperCase(),
              style: t.labelSmall?.copyWith(
                fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w700,
                letterSpacing: 0.66, color: tokens.fgMuted,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              '${item.hitRatePercent} %',
              style: t.titleMedium?.copyWith(
                fontSize: 18, fontWeight: FontWeight.w700, color: tokens.fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              item.subtitle,
              style: t.bodyMedium?.copyWith(fontSize: 13, color: tokens.fgMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
