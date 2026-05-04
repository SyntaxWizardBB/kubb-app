import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/stats/application/stats_filter_notifier.dart';
import 'package:kubb_app/features/stats/data/stats_filter.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Compact summary of active stats filters above the body. Renders nothing
/// when every filter sits at its default; otherwise shows one chip per active
/// dimension.
class ActiveFilterTags extends ConsumerWidget {
  const ActiveFilterTags({required this.isFinisseur, super.key});

  final bool isFinisseur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final f = ref.watch(statsFilterProvider);
    final tags = <String>[
      if (!isFinisseur && !f.isDistanceFullRange)
        l.statsFilterDistanceRange(
          f.distanceMin.toStringAsFixed(1),
          f.distanceMax.toStringAsFixed(1),
        ),
      if (isFinisseur && !f.isFieldFullRange)
        l.statsFilterFieldRange(f.finFieldMin, f.finFieldMax),
      if (isFinisseur && !f.isBaseFullRange)
        l.statsFilterBaseRange(f.finBaseMin, f.finBaseMax),
      if (f.dateRange == StatsDateRange.last7Days) l.statsRangeLast7Days,
      if (f.dateRange == StatsDateRange.last30Days) l.statsRangeLast30Days,
    ];

    if (tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space2,
        KubbTokens.space4,
        0,
      ),
      child: Wrap(
        spacing: KubbTokens.space2,
        runSpacing: KubbTokens.space2,
        children: [
          for (final t in tags) _Tag(label: t, tokens: tokens),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.tokens});

  final String label;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space3,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: tokens.bgRaised,
          borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
          border: Border.all(color: tokens.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: tokens.fgMuted,
          ),
        ),
      );
}
