import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/stats/application/stats_filter_notifier.dart';
import 'package:kubb_app/features/stats/data/stats_filter.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

const _distances = <double>[4, 4.5, 5, 5.5, 6, 6.5, 7, 7.5, 8];

class StatsFilterBar extends ConsumerWidget {
  const StatsFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final filter = ref.watch(statsFilterProvider);
    final notifier = ref.read(statsFilterProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(text: l.statsFilterDistance, tokens: tokens),
        const SizedBox(height: KubbTokens.space2),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _Chip(
                label: l.statsFilterAllDistances,
                selected: filter.distanceMeters == null,
                onTap: () => notifier.setDistance(null),
              ),
              for (final d in _distances)
                _Chip(
                  label: '${d.toStringAsFixed(1)} m',
                  selected: filter.distanceMeters == d,
                  onTap: () => notifier.setDistance(d),
                ),
            ],
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        _SectionLabel(text: l.statsFilterDateRange, tokens: tokens),
        const SizedBox(height: KubbTokens.space2),
        Wrap(
          spacing: KubbTokens.space2,
          children: [
            _Chip(
              label: l.statsRangeAll,
              selected: filter.dateRange == StatsDateRange.all,
              onTap: () => notifier.setDateRange(StatsDateRange.all),
            ),
            _Chip(
              label: l.statsRangeLast7Days,
              selected: filter.dateRange == StatsDateRange.last7Days,
              onTap: () => notifier.setDateRange(StatsDateRange.last7Days),
            ),
            _Chip(
              label: l.statsRangeLast30Days,
              selected: filter.dateRange == StatsDateRange.last30Days,
              onTap: () => notifier.setDateRange(StatsDateRange.last30Days),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.tokens});
  final String text;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.88,
              color: tokens.fgMuted,
            ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(right: KubbTokens.space2),
      child: Material(
        color: selected ? tokens.primary : tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
        child: InkWell(
          borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KubbTokens.space4,
              vertical: KubbTokens.space2,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? tokens.onPrimary : tokens.fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
