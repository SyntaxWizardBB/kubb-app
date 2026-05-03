import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class StatsTrendChart extends StatelessWidget {
  const StatsTrendChart({required this.points, super.key});

  final List<int> points;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);

    if (points.length < 2) {
      return _Placeholder(text: l.statsTrendEmpty, tokens: tokens);
    }

    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].toDouble()),
    ];

    return Container(
      height: 160,
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space2,
        KubbTokens.space4,
        KubbTokens.space4,
        KubbTokens.space2,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (_) => FlLine(
              color: tokens.line,
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: 25,
                getTitlesWidget: (value, _) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '${value.toInt()}',
                    style: TextStyle(fontSize: 10, color: tokens.fgMuted),
                  ),
                ),
              ),
            ),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: const AxisTitles(),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 2.5,
              color: tokens.primary,
              dotData: FlDotData(
                checkToShowDot: (spot, _) => spot.x == spots.last.x,
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: tokens.primary,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: tokens.primary.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.text, required this.tokens});

  final String text;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) => Container(
        height: 96,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(KubbTokens.space4),
        decoration: BoxDecoration(
          color: tokens.bgRaised,
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: tokens.fgMuted),
        ),
      );
}
