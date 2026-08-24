import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// One headline number on the overview.
@immutable
class AdminStat {
  const AdminStat({
    required this.label,
    required this.value,
    required this.note,
  });

  final String label;
  final String value;
  final String note;
}

/// How urgent a task is; drives the dot on the left of the row.
enum AdminTaskUrgency { normal, warning, critical }

/// One entry in the organiser's to-do list.
@immutable
class AdminTask {
  const AdminTask({
    required this.title,
    required this.meta,
    required this.callToAction,
    this.urgency = AdminTaskUrgency.normal,
  });

  final String title;
  final String meta;
  final String callToAction;
  final AdminTaskUrgency urgency;
}

/// One row of the standings card.
@immutable
class AdminStandingsRow {
  const AdminStandingsRow({
    required this.rank,
    required this.team,
    required this.record,
    required this.points,
  });

  final int rank;
  final String team;
  final String record;
  final int points;
}

/// The headline numbers, laid out as a reflowing grid of cards.
class AdminStatsRow extends StatelessWidget {
  const AdminStatsRow({required this.stats, super.key});

  final List<AdminStat> stats;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return LayoutBuilder(
      builder: (context, constraints) {
        const minTile = 210.0;
        const gap = KubbTokens.space3 + 2;
        final columns = ((constraints.maxWidth + gap) / (minTile + gap))
            .floor()
            .clamp(1, stats.isEmpty ? 1 : stats.length);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final stat in stats)
              SizedBox(
                width: width,
                child: _Card(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KubbTokens.space5,
                    vertical: 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Eyebrow(stat.label),
                      const SizedBox(height: KubbTokens.space1 + 2),
                      Text(
                        stat.value,
                        style: TextStyle(
                          fontSize: 38,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.14,
                          color: tokens.fg,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: KubbTokens.space1 + 2),
                      Text(
                        stat.note,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: tokens.fgMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The organiser's queue: what still needs a decision, with the action that
/// resolves it.
class AdminTasksCard extends StatelessWidget {
  const AdminTasksCard({required this.tasks, this.onTaskAction, super.key});

  final List<AdminTask> tasks;
  final ValueChanged<AdminTask>? onTaskAction;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, KubbTokens.space3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Eyebrow(l.adminTasksEyebrow),
                      const SizedBox(height: 3),
                      _CardTitle(l.adminTasksTitle),
                    ],
                  ),
                ),
                Text(
                  l.adminTasksOpenCount(tasks.length),
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    color: tokens.fgMuted,
                  ),
                ),
              ],
            ),
          ),
          for (final task in tasks)
            _TaskRow(
              task: task,
              onAction:
                  onTaskAction == null ? null : () => onTaskAction!(task),
            ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onAction});

  final AdminTask task;
  final VoidCallback? onAction;

  Color get _dotColor => switch (task.urgency) {
        AdminTaskUrgency.normal => KubbTokens.meadow500,
        AdminTaskUrgency.warning => KubbTokens.wood400,
        AdminTaskUrgency.critical => KubbTokens.miss,
      };

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: KubbTokens.space3 + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: tokens.fg,
                  ),
                ),
                Text(
                  task.meta,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: tokens.fgMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: KubbTokens.space3),
          SizedBox(
            height: 34,
            child: TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                backgroundColor: tokens.bgSunken,
                foregroundColor: tokens.fg,
                padding: const EdgeInsets.symmetric(
                  horizontal: KubbTokens.space3 + 2,
                ),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(task.callToAction),
            ),
          ),
        ],
      ),
    );
  }
}

/// The standings as they stood after the last completed round.
class AdminStandingsCard extends StatelessWidget {
  const AdminStandingsCard({
    required this.tournamentLabel,
    required this.afterRound,
    required this.rows,
    super.key,
  });

  final String tournamentLabel;
  final int afterRound;
  final List<AdminStandingsRow> rows;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, KubbTokens.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Eyebrow(l.adminStandingsEyebrow(afterRound)),
                const SizedBox(height: 3),
                _CardTitle(tournamentLabel),
              ],
            ),
          ),
          for (final row in rows) _StandingsRow(row: row),
        ],
      ),
    );
  }
}

class _StandingsRow extends StatelessWidget {
  const _StandingsRow({required this.row});

  final AdminStandingsRow row;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    // The top three carry the qualification tint; the rest stay quiet.
    final promoted = row.rank <= 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: promoted ? KubbTokens.meadow50 : tokens.bgSunken,
              borderRadius: BorderRadius.circular(KubbTokens.radiusSm + 2),
            ),
            child: Text(
              '${row.rank}',
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: promoted ? KubbTokens.meadow700 : tokens.fgMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: Text(
              row.team,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: tokens.fg,
              ),
            ),
          ),
          const SizedBox(width: KubbTokens.space3),
          Text(
            row.record,
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              color: tokens.fgMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: KubbTokens.space3),
          SizedBox(
            width: 26,
            child: Text(
              '${row.points}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 16,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: tokens.fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0C0B07),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.9,
        color: tokens.fgMuted,
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.18,
        color: tokens.fg,
      ),
    );
  }
}
