import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Schedule control bar for the per-tournament organizer dashboard detail
/// (ADR-0031 Phase B, Block B4). Surfaces the four schedule-control actions
/// that map 1:1 onto `TournamentActions`:
///
/// * **Start / Pause / Resume** — the primary clock toggle: Start while no
///   round is running yet, Pause while running, Resume while paused. Driven
///   by `TournamentActions.pause` / `.resume` (and `.startTournament` for the
///   initial start, wired by the screen).
/// * **Skip forward** — `TournamentActions.skipForward`. This is the
///   irreversible/destructive control (it forces the round to start running
///   NOW, abandoning the remaining call/break window), so it is guarded by a
///   PRESS-AND-HOLD gesture ([_HoldToConfirmButton]). NOTE: Phase A's
///   `round_phase_countdown.dart` "Hold" is the `awaiting_results` frozen-clock
///   banner (a schedule-status read-out), not a confirmation gesture, so there
///   is no A4 hold-gesture widget to share; this confirmation affordance is
///   defined here.
/// * **Skip back** — `TournamentActions.skipBack` (OE-B4: re-call the window,
///   not a true rewind).
///
/// All styling is via [KubbTokens]; the control buttons reuse [KubbButton] and
/// honour the 48 dp touch minimum (the primary toggle is the comfortable
/// 64 dp). Visual reference: `docs/design/ui_kits/app/TournamentScreen.jsx`
/// action row.
class ScheduleControlBar extends StatelessWidget {
  const ScheduleControlBar({
    required this.scheduleStatus,
    required this.paused,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onSkipForward,
    required this.onSkipBack,
    required this.onExtend,
    required this.onShorten,
    this.roundNumber,
    this.remainingSeconds,
    this.stepSeconds = 60,
    this.skipForwardHoldDuration = const Duration(milliseconds: 700),
    super.key,
  });

  /// Status of the active round's schedule (`null` while no schedule row
  /// exists yet — then only Start is offered).
  final RoundStatus? scheduleStatus;

  /// Whether the tournament-wide pause is currently active (K5 — pause lives
  /// on the active schedule row).
  final bool paused;

  /// Active round number for the status read-out ("Runde N"), or `null` when
  /// no round is live yet.
  final int? roundNumber;

  /// Remaining seconds of the live round for the status read-out, or `null`
  /// when unknown / no round is live.
  final int? remainingSeconds;

  final VoidCallback? onStart;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onSkipForward;
  final VoidCallback? onSkipBack;

  /// Lengthen the live round by the given number of seconds (spec §6/§9.5).
  final ValueChanged<int>? onExtend;

  /// Shorten the live round by the given number of seconds (spec §6/§9.5).
  final ValueChanged<int>? onShorten;

  /// Step size of the +/- round-time buttons, in seconds (default 60).
  final int stepSeconds;

  /// Hold duration the irreversible skip-forward action requires before it
  /// confirms. Injectable so widget tests can drive a short hold.
  final Duration skipForwardHoldDuration;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final running = scheduleStatus == RoundStatus.running;

    return Container(
      padding: const EdgeInsets.all(KubbTokens.space4),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusLine(
            paused: paused,
            scheduleStatus: scheduleStatus,
            roundNumber: roundNumber,
            remainingSeconds: remainingSeconds,
          ),
          const SizedBox(height: KubbTokens.space3),
          // Primary clock toggle (Start / Pause / Resume).
          KubbButton(
            variant: paused
                ? KubbButtonVariant.primary
                : (running
                    ? KubbButtonVariant.secondary
                    : KubbButtonVariant.primary),
            size: KubbButtonSize.large,
            onPressed: _primaryAction(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_primaryIcon(running: running)),
                const SizedBox(width: KubbTokens.space2),
                Text(_primaryLabel(l, running: running)),
              ],
            ),
          ),
          const SizedBox(height: KubbTokens.space3),
          Row(
            children: [
              Expanded(
                // Skip back is reversible-ish (re-call the window) → plain tap.
                child: KubbButton(
                  variant: KubbButtonVariant.secondary,
                  onPressed: onSkipBack,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.rotateCcw),
                      const SizedBox(width: KubbTokens.space1),
                      Text(l.organizerActionSkipBack),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: KubbTokens.space2),
              Expanded(
                // Skip forward is irreversible (forces the round to run now) →
                // press-and-hold to confirm.
                child: _HoldToConfirmButton(
                  onConfirmed: onSkipForward,
                  icon: LucideIcons.fastForward,
                  label: l.organizerActionSkipForward,
                  hint: l.organizerActionSkipForwardHoldHint,
                  holdDuration: skipForwardHoldDuration,
                ),
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space3),
          _RoundTimeControls(
            stepSeconds: stepSeconds,
            onExtend: onExtend,
            onShorten: onShorten,
          ),
        ],
      ),
    );
  }

  VoidCallback? _primaryAction() {
    if (paused) return onResume;
    if (scheduleStatus == RoundStatus.running) return onPause;
    return onStart;
  }

  IconData _primaryIcon({required bool running}) {
    if (paused) return LucideIcons.play;
    if (running) return LucideIcons.pause;
    return LucideIcons.play;
  }

  String _primaryLabel(AppLocalizations l, {required bool running}) {
    if (paused) return l.organizerActionResume;
    if (running) return l.organizerActionPause;
    return l.organizerActionStart;
  }
}

/// Press-and-hold confirmation button for an irreversible action. The fill
/// progresses over [holdDuration]; releasing early cancels. On completion
/// [onConfirmed] fires once. A `null` [onConfirmed] disables the control.
///
/// A destructive schedule control (skip-forward) must be held, not tapped, so
/// an accidental brush never forces a round live. (Phase A4 exposes no such
/// confirmation-gesture widget — its "Hold" is a frozen-clock status banner —
/// so this affordance lives here.)
class _HoldToConfirmButton extends StatefulWidget {
  const _HoldToConfirmButton({
    required this.onConfirmed,
    required this.icon,
    required this.label,
    required this.hint,
    required this.holdDuration,
  });

  final VoidCallback? onConfirmed;
  final IconData icon;
  final String label;
  final String hint;
  final Duration holdDuration;

  @override
  State<_HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<_HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onConfirmed?.call();
        _controller.reset();
      }
    });

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    if (widget.onConfirmed == null) return;
    unawaited(_controller.forward(from: 0));
  }

  void _cancel() {
    if (_controller.status == AnimationStatus.forward) {
      _controller.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onConfirmed != null;
    return Semantics(
      button: true,
      label: '${widget.label} · ${widget.hint}',
      // Raw pointer Listener (not GestureDetector): a press-and-HOLD must begin
      // filling the moment the finger lands, without waiting for the tap
      // gesture arena to resolve (a surrounding scrollable would otherwise
      // defer onTapDown until release, breaking the hold affordance).
      child: Listener(
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _cancel(),
        onPointerCancel: (_) => _cancel(),
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: KubbTokens.wood100),
                ),
                // Hold-progress fill.
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: _controller.value,
                        child: const ColoredBox(color: KubbTokens.wood300),
                      ),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: KubbTokens.touchMin,
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.icon,
                          size: 18,
                          color: KubbTokens.wood700,
                        ),
                        const SizedBox(width: KubbTokens.space1),
                        Text(
                          widget.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: KubbTokens.wood700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Status read-out (spec §6 MUSS): shows what is currently running — "Pause"
/// while the tournament-wide pause is active, otherwise "Runde N" — with the
/// live round's remaining time underneath.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.paused,
    required this.scheduleStatus,
    required this.roundNumber,
    required this.remainingSeconds,
  });

  final bool paused;
  final RoundStatus? scheduleStatus;
  final int? roundNumber;
  final int? remainingSeconds;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);

    final String title;
    if (paused) {
      title = l.organizerScheduleStatusPaused;
    } else if (roundNumber != null) {
      title = l.organizerRoundLabel(roundNumber!);
    } else {
      title = l.organizerScheduleStatusNone;
    }

    final remaining = remainingSeconds;
    final String time;
    if (remaining == null) {
      time = l.organizerScheduleStatusNone;
    } else if (remaining <= 0) {
      time = l.organizerDashboardExpired;
    } else {
      time = l.organizerDashboardRemaining(_formatSeconds(remaining));
    }
    final expired = remaining != null && remaining <= 0;

    return Row(
      children: [
        Icon(
          paused ? LucideIcons.pause : LucideIcons.radio,
          size: 16,
          color: tokens.fgMuted,
        ),
        const SizedBox(width: KubbTokens.space2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: tokens.fg,
                ),
              ),
              Text(
                time,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: expired ? KubbTokens.miss : tokens.fgMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatSeconds(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// Round-time adjust controls (spec §6/§9.5 MUSS): a minus and a plus step
/// button (default ±[stepSeconds]) plus a direct seconds input. The step
/// buttons fire [onShorten]/[onExtend] with the step; the input submits its
/// value as an extend (positive) or shorten (negative number).
class _RoundTimeControls extends StatefulWidget {
  const _RoundTimeControls({
    required this.stepSeconds,
    required this.onExtend,
    required this.onShorten,
  });

  final int stepSeconds;
  final ValueChanged<int>? onExtend;
  final ValueChanged<int>? onShorten;

  @override
  State<_RoundTimeControls> createState() => _RoundTimeControlsState();
}

class _RoundTimeControlsState extends State<_RoundTimeControls> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitInput() {
    final raw = _controller.text.trim();
    final value = int.tryParse(raw);
    if (value == null || value == 0) return;
    if (value > 0) {
      widget.onExtend?.call(value);
    } else {
      widget.onShorten?.call(-value);
    }
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final enabled = widget.onExtend != null && widget.onShorten != null;
    final stepLabel = l.organizerRoundTimeStep(widget.stepSeconds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.organizerRoundTimeTitle,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Row(
          children: [
            _StepButton(
              icon: LucideIcons.minus,
              label: stepLabel,
              semanticsLabel: l.organizerRoundTimeShorten,
              onPressed:
                  enabled ? () => widget.onShorten!(widget.stepSeconds) : null,
            ),
            const SizedBox(width: KubbTokens.space2),
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                textAlign: TextAlign.center,
                onSubmitted: (_) => _submitInput(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tokens.fg,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l.organizerRoundTimeInputHint,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: KubbTokens.space2,
                    vertical: KubbTokens.space3,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
                    borderSide: BorderSide(color: tokens.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
                    borderSide: BorderSide(color: tokens.line),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(LucideIcons.check, size: 16),
                    onPressed: enabled ? _submitInput : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: KubbTokens.space2),
            _StepButton(
              icon: LucideIcons.plus,
              label: stepLabel,
              semanticsLabel: l.organizerRoundTimeExtend,
              onPressed:
                  enabled ? () => widget.onExtend!(widget.stepSeconds) : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// A square +/- step button for the round-time controls, honouring the 48 dp
/// touch minimum.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String semanticsLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: KubbTokens.touchMin,
              minWidth: KubbTokens.touchMin,
            ),
            padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space2),
            decoration: BoxDecoration(
              color: KubbTokens.wood100,
              borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: KubbTokens.wood700),
                const SizedBox(width: KubbTokens.space1),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KubbTokens.wood700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
