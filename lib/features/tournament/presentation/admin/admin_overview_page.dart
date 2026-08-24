import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/breakpoints.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/presentation/admin/admin_overview_blocks.dart';
import 'package:kubb_app/features/tournament/presentation/admin/admin_page_header.dart';
import 'package:kubb_app/features/tournament/presentation/admin/live_round_panel.dart';

/// Everything the organiser overview shows, as one value: the running round,
/// the headline numbers, the queue and the table. Assembled by the caller so
/// the page itself stays free of providers.
@immutable
class AdminOverviewData {
  const AdminOverviewData({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.tournamentLabel,
    required this.round,
    required this.roundTotal,
    required this.courts,
    required this.timerDisplay,
    required this.timerRunning,
    required this.roundLengthsMinutes,
    required this.selectedRoundLengthMinutes,
    required this.stats,
    required this.tasks,
    required this.standings,
    this.paused = false,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String tournamentLabel;
  final int round;
  final int roundTotal;
  final List<LiveCourt> courts;
  final String timerDisplay;
  final bool timerRunning;
  final bool paused;
  final List<int> roundLengthsMinutes;
  final int selectedRoundLengthMinutes;
  final List<AdminStat> stats;
  final List<AdminTask> tasks;
  final List<AdminStandingsRow> standings;
}

/// The `overview` section of the organiser desktop surface.
class AdminOverviewPage extends StatelessWidget {
  const AdminOverviewPage({
    required this.data,
    this.onExport,
    this.onCreateTournament,
    this.onPauseToggle,
    this.onCloseRound,
    this.onTimerToggle,
    this.onTimerNudge,
    this.onTimerReset,
    this.onRoundLengthSelected,
    this.onCourtDetails,
    this.onTaskAction,
    super.key,
  });

  final AdminOverviewData data;
  final VoidCallback? onExport;
  final VoidCallback? onCreateTournament;
  final VoidCallback? onPauseToggle;
  final VoidCallback? onCloseRound;
  final VoidCallback? onTimerToggle;
  final ValueChanged<int>? onTimerNudge;
  final VoidCallback? onTimerReset;
  final ValueChanged<int>? onRoundLengthSelected;
  final ValueChanged<LiveCourt>? onCourtDetails;
  final ValueChanged<AdminTask>? onTaskAction;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminPageHeader(
            eyebrow: data.eyebrow,
            title: data.title,
            subtitle: data.subtitle,
            onExport: onExport,
            onCreateTournament: onCreateTournament,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(36, KubbTokens.space6, 36, 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LiveRoundPanel(
                    tournamentLabel: data.tournamentLabel,
                    round: data.round,
                    roundTotal: data.roundTotal,
                    courts: data.courts,
                    timerDisplay: data.timerDisplay,
                    timerRunning: data.timerRunning,
                    paused: data.paused,
                    roundLengthsMinutes: data.roundLengthsMinutes,
                    selectedRoundLengthMinutes: data.selectedRoundLengthMinutes,
                    onPauseToggle: onPauseToggle,
                    onCloseRound: onCloseRound,
                    onTimerToggle: onTimerToggle,
                    onTimerNudge: onTimerNudge,
                    onTimerReset: onTimerReset,
                    onRoundLengthSelected: onRoundLengthSelected,
                    onCourtDetails: onCourtDetails,
                  ),
                  const SizedBox(height: KubbTokens.space5),
                  AdminStatsRow(stats: data.stats),
                  const SizedBox(height: KubbTokens.space5),
                  _TasksAndStandings(
                    tasks: data.tasks,
                    standings: data.standings,
                    tournamentLabel: data.tournamentLabel,
                    afterRound: data.round - 1,
                    onTaskAction: onTaskAction,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

class _TasksAndStandings extends StatelessWidget {
  const _TasksAndStandings({
    required this.tasks,
    required this.standings,
    required this.tournamentLabel,
    required this.afterRound,
    required this.onTaskAction,
  });

  final List<AdminTask> tasks;
  final List<AdminStandingsRow> standings;
  final String tournamentLabel;
  final int afterRound;
  final ValueChanged<AdminTask>? onTaskAction;

  @override
  Widget build(BuildContext context) {
    final tasksCard = AdminTasksCard(tasks: tasks, onTaskAction: onTaskAction);
    final standingsCard = AdminStandingsCard(
      tournamentLabel: tournamentLabel,
      afterRound: afterRound,
      rows: standings,
    );
    return KubbResponsive(
      builder: (context, breakpoint) {
        // Side by side only once there is room for both to stay readable;
        // below that the queue comes first, because it is what needs a
        // decision.
        if (!breakpoint.isExpanded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tasksCard,
              const SizedBox(height: 18),
              standingsCard,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: tasksCard),
            const SizedBox(width: 18),
            Expanded(flex: 4, child: standingsCard),
          ],
        );
      },
    );
  }
}
