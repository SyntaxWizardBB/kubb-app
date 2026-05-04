import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_bottom_sheet.dart';
import 'package:kubb_app/features/stats/application/stats_filter_notifier.dart';
import 'package:kubb_app/features/stats/data/stats_filter.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Bottom-sheet that edits the stats filter for the active tab. Sniper tab
/// gets the distance slider, finisseur tab gets field plus base sliders.
/// Both share the date-range chips.
class StatsFilterModal extends ConsumerStatefulWidget {
  const StatsFilterModal({required this.isFinisseur, super.key});

  final bool isFinisseur;

  static Future<void> show(BuildContext context, {required bool finisseur}) {
    return showKubbBottomSheet<void>(
      context,
      builder: (_) => StatsFilterModal(isFinisseur: finisseur),
    );
  }

  @override
  ConsumerState<StatsFilterModal> createState() => _StatsFilterModalState();
}

class _StatsFilterModalState extends ConsumerState<StatsFilterModal> {
  late StatsFilter _draft;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(statsFilterProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: KubbTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.statsFilterTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: tokens.fg,
            ),
          ),
          const SizedBox(height: KubbTokens.space4),
          if (widget.isFinisseur) ...[
            _IntRangeBlock(
              label: l.statsFilterFinisseurField,
              min: 0,
              max: 10,
              current: RangeValues(
                _draft.finFieldMin.toDouble(),
                _draft.finFieldMax.toDouble(),
              ),
              onChanged: (v) => setState(
                () => _draft = _draft.copyWith(
                  finFieldMin: v.start.round(),
                  finFieldMax: v.end.round(),
                ),
              ),
            ),
            const SizedBox(height: KubbTokens.space4),
            _IntRangeBlock(
              label: l.statsFilterFinisseurBase,
              min: 0,
              max: 5,
              current: RangeValues(
                _draft.finBaseMin.toDouble(),
                _draft.finBaseMax.toDouble(),
              ),
              onChanged: (v) => setState(
                () => _draft = _draft.copyWith(
                  finBaseMin: v.start.round(),
                  finBaseMax: v.end.round(),
                ),
              ),
            ),
          ] else ...[
            _DoubleRangeBlock(
              label: l.statsFilterDistance,
              min: 4,
              max: 8,
              divisions: 8,
              current: RangeValues(_draft.distanceMin, _draft.distanceMax),
              labelFor: (v) => '${v.toStringAsFixed(1)} m',
              onChanged: (v) => setState(
                () => _draft = _draft.copyWith(
                  distanceMin: _round(v.start),
                  distanceMax: _round(v.end),
                ),
              ),
            ),
          ],
          const SizedBox(height: KubbTokens.space4),
          Text(
            l.statsFilterDateRange.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.88,
              color: tokens.fgMuted,
            ),
          ),
          const SizedBox(height: KubbTokens.space2),
          Wrap(
            spacing: KubbTokens.space2,
            children: [
              _RangeChip(
                label: l.statsRangeAll,
                selected: _draft.dateRange == StatsDateRange.all,
                onTap: () => setState(
                  () => _draft = _draft.copyWith(dateRange: StatsDateRange.all),
                ),
              ),
              _RangeChip(
                label: l.statsRangeLast7Days,
                selected: _draft.dateRange == StatsDateRange.last7Days,
                onTap: () => setState(
                  () => _draft = _draft.copyWith(
                    dateRange: StatsDateRange.last7Days,
                  ),
                ),
              ),
              _RangeChip(
                label: l.statsRangeLast30Days,
                selected: _draft.dateRange == StatsDateRange.last30Days,
                onTap: () => setState(
                  () => _draft = _draft.copyWith(
                    dateRange: StatsDateRange.last30Days,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space5),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: KubbTokens.touchComfortable,
                  child: OutlinedButton(
                    onPressed: () => setState(() => _draft = const StatsFilter()),
                    child: Text(l.statsFilterReset),
                  ),
                ),
              ),
              const SizedBox(width: KubbTokens.space3),
              Expanded(
                child: SizedBox(
                  height: KubbTokens.touchComfortable,
                  child: FilledButton(
                    onPressed: () {
                      ref.read(statsFilterProvider.notifier).replace(_draft);
                      Navigator.of(context).pop();
                    },
                    child: Text(l.statsFilterApply),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _round(double v) => (v * 2).round() / 2.0;
}

class _DoubleRangeBlock extends StatelessWidget {
  const _DoubleRangeBlock({
    required this.label,
    required this.min,
    required this.max,
    required this.divisions,
    required this.current,
    required this.onChanged,
    required this.labelFor,
  });

  final String label;
  final double min;
  final double max;
  final int divisions;
  final RangeValues current;
  final ValueChanged<RangeValues> onChanged;
  final String Function(double) labelFor;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.88,
                color: tokens.fgMuted,
              ),
            ),
            Text(
              '${labelFor(current.start)}  –  ${labelFor(current.end)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: tokens.fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        RangeSlider(
          min: min,
          max: max,
          divisions: divisions,
          values: current,
          labels: RangeLabels(labelFor(current.start), labelFor(current.end)),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _IntRangeBlock extends StatelessWidget {
  const _IntRangeBlock({
    required this.label,
    required this.min,
    required this.max,
    required this.current,
    required this.onChanged,
  });

  final String label;
  final int min;
  final int max;
  final RangeValues current;
  final ValueChanged<RangeValues> onChanged;

  @override
  Widget build(BuildContext context) {
    return _DoubleRangeBlock(
      label: label,
      min: min.toDouble(),
      max: max.toDouble(),
      divisions: max - min,
      current: current,
      onChanged: onChanged,
      labelFor: (v) => v.round().toString(),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
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
    return Material(
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
    );
  }
}
