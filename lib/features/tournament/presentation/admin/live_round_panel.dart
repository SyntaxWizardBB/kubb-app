import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// One pitch as the live panel shows it.
@immutable
class LiveCourt {
  const LiveCourt({
    required this.name,
    required this.home,
    required this.away,
    required this.score,
    required this.done,
  });

  final String name;
  final String home;
  final String away;
  final String score;
  final bool done;
}

/// The dark hero of the organiser overview: which round is running, how far it
/// has got, the round clock, and a card per pitch.
///
/// Takes its state and its callbacks from the caller — the panel neither ticks
/// the clock nor talks to a repository.
class LiveRoundPanel extends StatelessWidget {
  const LiveRoundPanel({
    required this.tournamentLabel,
    required this.round,
    required this.roundTotal,
    required this.courts,
    required this.timerDisplay,
    required this.timerRunning,
    required this.roundLengthsMinutes,
    required this.selectedRoundLengthMinutes,
    this.paused = false,
    this.onPauseToggle,
    this.onCloseRound,
    this.onTimerToggle,
    this.onTimerNudge,
    this.onTimerReset,
    this.onRoundLengthSelected,
    this.onCourtDetails,
    super.key,
  });

  final String tournamentLabel;
  final int round;
  final int roundTotal;
  final List<LiveCourt> courts;
  final String timerDisplay;
  final bool timerRunning;
  final List<int> roundLengthsMinutes;
  final int selectedRoundLengthMinutes;
  final bool paused;
  final VoidCallback? onPauseToggle;
  final VoidCallback? onCloseRound;
  final VoidCallback? onTimerToggle;

  /// Negative for back, positive for forward, in minutes.
  final ValueChanged<int>? onTimerNudge;
  final VoidCallback? onTimerReset;
  final ValueChanged<int>? onRoundLengthSelected;
  final ValueChanged<LiveCourt>? onCourtDetails;

  int get _doneCount => courts.where((c) => c.done).length;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space6 + 2,
        vertical: KubbTokens.space6,
      ),
      decoration: BoxDecoration(
        color: KubbTokens.stone900,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Headline(
            tournamentLabel: tournamentLabel,
            paused: paused,
            onPauseToggle: onPauseToggle,
            onCloseRound: onCloseRound,
          ),
          const SizedBox(height: KubbTokens.space5),
          _RoundProgress(
            label: l.adminRoundOf(round, roundTotal),
            trailing: l.adminCourtsDone(_doneCount, courts.length),
            fraction: courts.isEmpty ? 0 : _doneCount / courts.length,
          ),
          const SizedBox(height: KubbTokens.space5),
          _TimerRow(
            display: timerDisplay,
            running: timerRunning,
            lengths: roundLengthsMinutes,
            selectedLength: selectedRoundLengthMinutes,
            onToggle: onTimerToggle,
            onNudge: onTimerNudge,
            onReset: onTimerReset,
            onLengthSelected: onRoundLengthSelected,
          ),
          const SizedBox(height: KubbTokens.space5),
          _CourtGrid(courts: courts, onDetails: onCourtDetails),
        ],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({
    required this.tournamentLabel,
    required this.paused,
    required this.onPauseToggle,
    required this.onCloseRound,
  });

  final String tournamentLabel;
  final bool paused;
  final VoidCallback? onPauseToggle;
  final VoidCallback? onCloseRound;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: KubbTokens.space4,
      runSpacing: KubbTokens.space3,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: KubbTokens.miss,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: KubbTokens.space2),
            Text(
              l.adminLiveBadge.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.32,
                color: KubbTokens.chalk50,
              ),
            ),
          ],
        ),
        Text(
          tournamentLabel,
          style: const TextStyle(
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.56,
            color: KubbTokens.chalk50,
          ),
        ),
        Wrap(
          spacing: KubbTokens.space2,
          runSpacing: KubbTokens.space2,
          children: [
            _PanelButton(
              label: paused
                  ? l.adminActionResumeRound
                  : l.adminActionPauseRound,
              onPressed: onPauseToggle,
            ),
            _PanelButton(
              label: l.adminActionCloseRound,
              onPressed: onCloseRound,
              accent: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _RoundProgress extends StatelessWidget {
  const _RoundProgress({
    required this.label,
    required this.trailing,
    required this.fraction,
  });

  final String label;
  final String trailing;
  final double fraction;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Flexible(
            child: Text(
              label.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 1.2,
                letterSpacing: 0.88,
                color: KubbTokens.stone300,
              ),
            ),
          ),
          const SizedBox(width: KubbTokens.space3 + 2),
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: const Color(0x1FFFFFFF),
                valueColor: const AlwaysStoppedAnimation(KubbTokens.meadow400),
              ),
            ),
          ),
          const SizedBox(width: KubbTokens.space3 + 2),
          Flexible(
            child: Text(
              trailing,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 1.2,
                color: KubbTokens.stone300,
              ),
            ),
          ),
        ],
      );
}

class _TimerRow extends StatelessWidget {
  const _TimerRow({
    required this.display,
    required this.running,
    required this.lengths,
    required this.selectedLength,
    required this.onToggle,
    required this.onNudge,
    required this.onReset,
    required this.onLengthSelected,
  });

  final String display;
  final bool running;
  final List<int> lengths;
  final int selectedLength;
  final VoidCallback? onToggle;
  final ValueChanged<int>? onNudge;
  final VoidCallback? onReset;
  final ValueChanged<int>? onLengthSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space5,
        vertical: KubbTokens.space4,
      ),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: KubbTokens.space6,
        runSpacing: KubbTokens.space4,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _PanelCaption(l.adminRoundTimeLabel),
              const SizedBox(height: KubbTokens.space1),
              Text(
                display,
                style: const TextStyle(
                  fontSize: 44,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.76,
                  color: KubbTokens.chalk50,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: KubbTokens.space2,
            runSpacing: KubbTokens.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _PanelButton(
                label: l.adminTimerBack,
                onPressed: onNudge == null ? null : () => onNudge!(-1),
              ),
              _PanelButton(
                label: running ? l.adminTimerPause : l.adminTimerStart,
                onPressed: onToggle,
                accent: true,
              ),
              _PanelButton(
                label: l.adminTimerForward,
                onPressed: onNudge == null ? null : () => onNudge!(1),
              ),
              _PanelButton(
                label: l.adminTimerReset,
                onPressed: onReset,
                quiet: true,
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _PanelCaption(l.adminRoundLengthLabel),
              const SizedBox(height: KubbTokens.space1 + 2),
              Wrap(
                spacing: KubbTokens.space1 + 2,
                runSpacing: KubbTokens.space1 + 2,
                children: [
                  for (final minutes in lengths)
                    _LengthChip(
                      minutes: minutes,
                      selected: minutes == selectedLength,
                      onPressed: onLengthSelected == null
                          ? null
                          : () => onLengthSelected!(minutes),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CourtGrid extends StatelessWidget {
  const _CourtGrid({required this.courts, required this.onDetails});

  final List<LiveCourt> courts;
  final ValueChanged<LiveCourt>? onDetails;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const minTile = 280.0;
          const gap = KubbTokens.space3;
          final columns =
              ((constraints.maxWidth + gap) / (minTile + gap)).floor().clamp(1, 4);
          final tileWidth =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final court in courts)
                SizedBox(
                  width: tileWidth,
                  child: _CourtCard(
                    court: court,
                    onDetails:
                        onDetails == null ? null : () => onDetails!(court),
                  ),
                ),
            ],
          );
        },
      );
}

class _CourtCard extends StatelessWidget {
  const _CourtCard({required this.court, required this.onDetails});

  final LiveCourt court;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space4),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(
          color: court.done ? KubbTokens.meadow400 : const Color(0x1FFFFFFF),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            court.name.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.88,
              color: KubbTokens.stone300,
            ),
          ),
          const SizedBox(height: KubbTokens.space3),
          Row(
            children: [
              Expanded(
                child: Text(
                  court.home,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: KubbTokens.chalk50,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KubbTokens.space3,
                ),
                child: Text(
                  court.score,
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: KubbTokens.chalk50,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  court.away,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: KubbTokens.chalk50,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space3 + 2),
          Align(
            alignment: Alignment.centerLeft,
            child: _PanelButton(
              label: l.adminCourtDetails,
              onPressed: onDetails,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelCaption extends StatelessWidget {
  const _PanelCaption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.9,
          color: KubbTokens.stone300,
        ),
      );
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.label,
    required this.onPressed,
    this.accent = false,
    this.quiet = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool accent;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final background = accent
        ? KubbTokens.meadow400
        : quiet
            ? Colors.transparent
            : const Color(0x1AFFFFFF);
    final foreground = accent
        ? KubbTokens.stone900
        : quiet
            ? KubbTokens.stone300
            : KubbTokens.chalk50;
    return SizedBox(
      height: 40,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          textStyle: TextStyle(
            fontSize: 13,
            fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _LengthChip extends StatelessWidget {
  const _LengthChip({
    required this.minutes,
    required this.selected,
    required this.onPressed,
  });

  final int minutes;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 30,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor:
                selected ? KubbTokens.chalk50 : const Color(0x14FFFFFF),
            foregroundColor:
                selected ? KubbTokens.stone900 : KubbTokens.stone300,
            padding:
                const EdgeInsets.symmetric(horizontal: KubbTokens.space2 + 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Text("$minutes'"),
        ),
      );
}
