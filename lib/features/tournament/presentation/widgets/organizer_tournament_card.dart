import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_status_pill.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Overview card for ONE administrable tournament on the organizer dashboard
/// (ADR-0031 Phase B, Block B4). Renders the tournament name + lifecycle
/// status, the active phase/round, the schedule status, a live remaining-time
/// readout, the open- and disputed-match badges, plus at least one quick
/// action (Start when the tournament has no running schedule yet, else
/// Pause/Resume of the tournament-wide clock) and a deep-link into the
/// per-tournament detail.
///
/// This card is the ACTION surface — NOT read-only (the read-only dashboard
/// removed in `a46f962` is the anti-pattern). All styling comes from
/// [KubbTokens]; the design follows `docs/design/ui_kits/app/TournamentScreen.jsx`
/// (raised tile, mono meta line, pill badges).
class OrganizerTournamentCard extends StatelessWidget {
  const OrganizerTournamentCard({
    required this.card,
    required this.serverOffset,
    required this.onOpenDetail,
    required this.onPrimaryAction,
    this.ticker,
    super.key,
  });

  /// The administrable-tournament projection driving the card.
  final TournamentAdminCardRef card;

  /// Server-clock skew offset (from `serverClockOffsetProvider`) so the live
  /// remaining-time readout is server-corrected (ADR-0031 §Uhr).
  final Duration serverOffset;

  /// Opens the per-tournament dashboard detail.
  final VoidCallback onOpenDetail;

  /// The quick action: Start when not yet running, else Pause/Resume of the
  /// tournament-wide clock. `null` disables the button (e.g. for terminal
  /// tournaments).
  final VoidCallback? onPrimaryAction;

  /// Injectable 1-second UI render ticker (tests pass a manual stream). Pure
  /// rendering only — NO server fetch (ADR-0029 / DoD-14). Defaults to a real
  /// `Stream.periodic` opened lazily by the countdown.
  final Stream<void>? ticker;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final paused = card.pausedAt != null;
    final running = card.scheduleStatus == RoundStatus.running;

    return Container(
      padding: const EdgeInsets.all(KubbTokens.space4),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  card.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.2,
                    color: tokens.fg,
                  ),
                ),
              ),
              const SizedBox(width: KubbTokens.space2),
              TournamentStatusPill(status: card.status),
            ],
          ),
          const SizedBox(height: KubbTokens.space2),
          Row(
            children: [
              KubbIcon.lucide(
                LucideIcons.layers,
                size: 14,
                color: tokens.fgMuted,
              ),
              const SizedBox(width: KubbTokens.space1),
              Text(
                card.currentRound != null
                    ? l.organizerDashboardCurrentRound(card.currentRound!)
                    : l.organizerDashboardNoRound,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.fgMuted,
                ),
              ),
              const SizedBox(width: KubbTokens.space2),
              _ScheduleStatusChip(
                status: card.scheduleStatus,
                paused: paused,
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space2),
          _RemainingTime(
            // While paused the clock is frozen — show the captured baseline,
            // do not tick (ADR-0031 §Modell: pausedAt stops the live slice).
            remainingSeconds: card.remainingSeconds,
            frozen: paused || !running,
            serverOffset: serverOffset,
            ticker: ticker,
          ),
          const SizedBox(height: KubbTokens.space3),
          Wrap(
            spacing: KubbTokens.space2,
            runSpacing: KubbTokens.space2,
            children: [
              _CountBadge(
                icon: LucideIcons.listChecks,
                label: l.organizerDashboardOpenMatches(card.openMatchCount),
                emphasised: card.openMatchCount > 0,
                tone: _BadgeTone.neutral,
              ),
              _CountBadge(
                icon: LucideIcons.triangle,
                label:
                    l.organizerDashboardDisputedMatches(card.disputedMatchCount),
                emphasised: card.disputedMatchCount > 0,
                tone: _BadgeTone.danger,
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space4),
          Row(
            children: [
              Expanded(
                child: KubbButton(
                  variant: KubbButtonVariant.primary,
                  onPressed: onPrimaryAction,
                  child: Text(_primaryLabel(l, running: running, paused: paused)),
                ),
              ),
              const SizedBox(width: KubbTokens.space2),
              Expanded(
                child: KubbButton(
                  variant: KubbButtonVariant.secondary,
                  onPressed: onOpenDetail,
                  child: Text(l.organizerOpenDetail),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _primaryLabel(
    AppLocalizations l, {
    required bool running,
    required bool paused,
  }) {
    if (paused) return l.organizerActionResume;
    if (running) return l.organizerActionPause;
    return l.organizerActionStart;
  }
}

/// Small coloured chip mapping a [RoundStatus] (plus the paused flag) to a
/// short German label. Mirrors [TournamentStatusPill]'s visual language.
class _ScheduleStatusChip extends StatelessWidget {
  const _ScheduleStatusChip({required this.status, required this.paused});

  final RoundStatus? status;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final (label, bg, fg) = _spec(tokens, l);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  (String, Color, Color) _spec(KubbTokens tokens, AppLocalizations l) {
    if (paused) {
      return (
        l.organizerScheduleStatusPaused,
        KubbTokens.wood100,
        KubbTokens.wood600,
      );
    }
    switch (status) {
      case null:
        return (l.organizerScheduleStatusNone, tokens.bgSunken, tokens.fgMuted);
      case RoundStatus.published:
        return (
          l.organizerScheduleStatusPublished,
          KubbTokens.wood100,
          KubbTokens.wood600,
        );
      case RoundStatus.call:
        return (
          l.organizerScheduleStatusCall,
          KubbTokens.wood100,
          KubbTokens.wood600,
        );
      case RoundStatus.running:
        return (
          l.organizerScheduleStatusRunning,
          KubbTokens.meadow100,
          KubbTokens.meadow700,
        );
      case RoundStatus.awaitingResults:
        return (
          l.organizerScheduleStatusAwaiting,
          KubbTokens.miss.withValues(alpha: 0.15),
          KubbTokens.miss,
        );
      case RoundStatus.completed:
        return (
          l.organizerScheduleStatusCompleted,
          tokens.bgSunken,
          tokens.fgMuted,
        );
    }
  }
}

enum _BadgeTone { neutral, danger }

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.icon,
    required this.label,
    required this.emphasised,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final bool emphasised;
  final _BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final Color fg;
    final Color bg;
    if (emphasised && tone == _BadgeTone.danger) {
      fg = KubbTokens.miss;
      bg = KubbTokens.miss.withValues(alpha: 0.12);
    } else if (emphasised) {
      fg = KubbTokens.meadow700;
      bg = KubbTokens.meadow100;
    } else {
      fg = tokens.fgMuted;
      bg = tokens.bgSunken;
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space2,
        vertical: KubbTokens.space1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: KubbTokens.space1),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Live remaining-time readout. Captures the server-computed
/// [remainingSeconds] baseline and decrements it once per second via a PURE
/// UI ticker (ADR-0029: rendering only, no server fetch). When [frozen]
/// (tournament-wide pause active, or the round is not running) the value is
/// shown without ticking.
class _RemainingTime extends StatefulWidget {
  const _RemainingTime({
    required this.remainingSeconds,
    required this.frozen,
    required this.serverOffset,
    this.ticker,
  });

  final int? remainingSeconds;
  final bool frozen;
  final Duration serverOffset;
  final Stream<void>? ticker;

  @override
  State<_RemainingTime> createState() => _RemainingTimeState();
}

class _RemainingTimeState extends State<_RemainingTime> {
  late int? _remaining;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _remaining = widget.remainingSeconds;
    _maybeSubscribe();
  }

  @override
  void didUpdateWidget(_RemainingTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A fresh fetch (new baseline) re-anchors the countdown.
    if (oldWidget.remainingSeconds != widget.remainingSeconds) {
      _remaining = widget.remainingSeconds;
    }
    if (oldWidget.frozen != widget.frozen) {
      _maybeSubscribe();
    }
  }

  void _maybeSubscribe() {
    unawaited(_sub?.cancel());
    _sub = null;
    if (widget.frozen || _remaining == null) return;
    // Pure 1-second UI render ticker — the ONLY timer this feature may run
    // (ADR-0029 / DoD-14). It performs no server discovery; it just decrements
    // the already-fetched baseline so the readout counts down between fetches.
    final stream =
        widget.ticker ?? Stream<void>.periodic(const Duration(seconds: 1));
    _sub = stream.listen((_) {
      if (!mounted) return;
      setState(() {
        final current = _remaining;
        if (current != null) _remaining = current - 1;
      });
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final remaining = _remaining;
    final String text;
    if (remaining == null) {
      text = l.organizerScheduleStatusNone;
    } else if (remaining <= 0) {
      text = l.organizerDashboardExpired;
    } else {
      text = l.organizerDashboardRemaining(_format(remaining));
    }
    final expired = remaining != null && remaining <= 0;
    return Row(
      children: [
        KubbIcon.lucide(
          LucideIcons.timer,
          size: 14,
          color: expired ? KubbTokens.miss : tokens.fgMuted,
        ),
        const SizedBox(width: KubbTokens.space1),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: expired ? KubbTokens.miss : tokens.fg,
          ),
        ),
      ],
    );
  }

  String _format(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
