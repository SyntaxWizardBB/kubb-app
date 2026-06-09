import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/match_countdown.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Renders the right clock for the current round phase (ADR-0031 §Modell,
/// Phase-A Block A4).
///
/// Drives three states off the optional [schedule] row's
/// [TournamentRoundScheduleRef.status] (a [RoundStatus]) plus its frozen-ness
/// ([TournamentRoundScheduleRef.pausedAt] / a held round):
///
/// 1. **Call / pause countdown** — `published` or `call` while `now` is still
///    before `starts_at`: shows "Nächste Runde in mm:ss" counting down to the
///    round start. Uses the same server-corrected `now` as the match clock.
/// 2. **Match countdown** — `running`: delegates to the existing
///    [MatchCountdown] (server-/pause-corrected); this widget never re-derives
///    the remaining-time formula (that lives in `MatchTimer`/`MatchCountdown`).
/// 3. **Hold** — `awaiting_results` (or a tiebreak): a frozen clock
///    ([MatchCountdown.onHold]) plus a hold / tiebreak banner.
///
/// **Fallback `schedule == null`** (running legacy tournaments, OE-5): falls
/// back to the unchanged plain `started_at` clock — a [MatchCountdown] with
/// zero server offset and no pause/hold, so existing tournaments behave exactly
/// as before. No crash, no pause/hold view.
///
/// The widget owns no clock of its own: it reuses [MatchCountdown]'s ticker for
/// the call countdown too, so tests inject a [ManualCountdownTicker] and a
/// controllable [now] (no real timers, ADR-0029: no new server-state polling —
/// the 1s ticker is pure rendering).
class RoundPhaseCountdown extends StatelessWidget {
  const RoundPhaseCountdown({
    required this.startedAt,
    required this.durationSeconds,
    this.schedule,
    this.tiebreakAfterSeconds,
    this.serverOffset = Duration.zero,
    this.ticker,
    this.haptics = const HapticFeedbackCountdownHaptics(),
    this.now,
    super.key,
  });

  /// The matching `tournament_round_schedule` row, or `null` for legacy
  /// tournaments without a schedule line (then the plain `started_at` clock is
  /// rendered).
  final TournamentRoundScheduleRef? schedule;

  /// When the match clock started (match.started_at). Used for the running /
  /// hold / fallback match clock.
  final DateTime startedAt;

  /// Match time limit in seconds (match_format round_time_seconds /
  /// time_limit).
  final int durationSeconds;

  /// Optional tiebreak trigger offset, forwarded to [MatchCountdown].
  final int? tiebreakAfterSeconds;

  /// Skew offset between server and device clock (ADR-0031 §Uhr). Applied to
  /// the call countdown and forwarded to the running/hold [MatchCountdown].
  final Duration serverOffset;

  /// Ticker driving the 1s re-evaluation. Defaults to a wall-clock timer;
  /// widget tests inject a [ManualCountdownTicker].
  final CountdownTicker? ticker;

  /// Vibration sink, forwarded to the running/hold [MatchCountdown].
  final CountdownHaptics haptics;

  /// Clock source. Defaults to [DateTime.now]; tests inject a controllable
  /// callback so the clock can be stepped without real delays.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final s = schedule;

    // Fallback (OE-5 / A4-3): no schedule line -> the plain started_at clock,
    // exactly the legacy behaviour (zero offset is the caller's default; no
    // pause/hold).
    if (s == null) {
      return MatchCountdown(
        startedAt: startedAt,
        durationSeconds: durationSeconds,
        tiebreakAfterSeconds: tiebreakAfterSeconds,
        serverOffset: serverOffset,
        ticker: ticker,
        haptics: haptics,
        now: now,
      );
    }

    switch (s.status) {
      case RoundStatus.published:
      case RoundStatus.call:
        // Call/pause window: count down to starts_at. Once the start is
        // reached we fall through to the running clock (the cron/CDC will flip
        // the status to running, but rendering the clock immediately avoids a
        // dead second at the boundary).
        return _CallCountdown(
          startsAt: s.startsAt,
          serverOffset: serverOffset,
          ticker: ticker,
          now: now,
          // Once starts_at is reached, render the running match clock.
          runningBuilder: () => _matchClock(onHold: false),
        );
      case RoundStatus.running:
        return _matchClock(onHold: false);
      case RoundStatus.awaitingResults:
        // Hold: frozen clock + hold / tiebreak banner (ADR-0031 §6).
        return _HoldClock(
          startedAt: startedAt,
          durationSeconds: durationSeconds,
          tiebreakAfterSeconds: tiebreakAfterSeconds,
          serverOffset: serverOffset,
          ticker: ticker,
          haptics: haptics,
          now: now,
        );
      case RoundStatus.completed:
        // Round done — render the (held) match clock; the detail screen stops
        // showing the clock once the match itself is terminal anyway.
        return _matchClock(onHold: false);
    }
  }

  /// The running / fallback match clock, pause-corrected from the schedule row.
  MatchCountdown _matchClock({required bool onHold}) {
    final s = schedule;
    return MatchCountdown(
      startedAt: startedAt,
      durationSeconds: durationSeconds,
      tiebreakAfterSeconds: tiebreakAfterSeconds,
      serverOffset: serverOffset,
      pausedAt: s?.pausedAt,
      pausedAccumSeconds: s?.pausedAccumSeconds ?? 0,
      onHold: onHold,
      ticker: ticker,
      haptics: haptics,
      now: now,
    );
  }
}

/// Call/pause countdown: shows "Nächste Runde in mm:ss" until [startsAt],
/// reading the server-corrected clock on every tick. Once [startsAt] is
/// reached it renders [runningBuilder] (the running match clock), so the
/// transition needs no status push.
class _CallCountdown extends StatefulWidget {
  const _CallCountdown({
    required this.startsAt,
    required this.serverOffset,
    required this.runningBuilder,
    this.ticker,
    this.now,
  });

  final DateTime startsAt;
  final Duration serverOffset;
  final Widget Function() runningBuilder;
  final CountdownTicker? ticker;
  final DateTime Function()? now;

  @override
  State<_CallCountdown> createState() => _CallCountdownState();
}

class _CallCountdownState extends State<_CallCountdown> {
  late final CountdownTicker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = widget.ticker ?? WallClockCountdownTicker();
    _ticker.start(_onTick);
  }

  @override
  void dispose() {
    _ticker.stop();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {});
  }

  /// Server-corrected current time (ADR-0031 §Uhr), mirroring
  /// [MatchCountdown]'s clock so the call countdown agrees with the match clock.
  DateTime _nowValue() =>
      (widget.now ?? DateTime.now)().toUtc().add(widget.serverOffset);

  String _mmss(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.startsAt.difference(_nowValue());
    // starts_at reached: hand over to the running match clock.
    if (remaining <= Duration.zero) {
      return widget.runningBuilder();
    }

    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);

    return Container(
      key: const ValueKey('round-call-countdown'),
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: tokens.line),
      ),
      child: Row(children: [
        const Icon(Icons.hourglass_top_outlined, color: KubbTokens.wood400),
        const SizedBox(width: KubbTokens.space3),
        Expanded(
          child: Text(
            l.tournamentRoundCallCountdown(_mmss(remaining)),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: tokens.fg,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ]),
    );
  }
}

/// Hold state (`awaiting_results` / tiebreak): a frozen match clock plus a
/// hold / tiebreak banner. The frozen clock reuses [MatchCountdown] with
/// `onHold: true` so the remaining-time freeze stays in `MatchTimer` (A4-11).
class _HoldClock extends StatelessWidget {
  const _HoldClock({
    required this.startedAt,
    required this.durationSeconds,
    required this.tiebreakAfterSeconds,
    required this.serverOffset,
    required this.ticker,
    required this.haptics,
    required this.now,
  });

  final DateTime startedAt;
  final int durationSeconds;
  final int? tiebreakAfterSeconds;
  final Duration serverOffset;
  final CountdownTicker? ticker;
  final CountdownHaptics haptics;
  final DateTime Function()? now;

  /// Server-corrected current time (ADR-0031 §Uhr), mirroring [MatchCountdown]'s
  /// clock so the hold banner agrees with the match clock.
  DateTime _nowValue() =>
      (now ?? DateTime.now)().toUtc().add(serverOffset);

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    // Tiebreak vs. plain hold: RoundStatus has no dedicated tiebreak state
    // (tiebreak is emergent, ADR-0031 §6). Only call it a tiebreak when the
    // server-corrected clock has actually crossed the tiebreak point — a
    // configured tiebreak window alone (the result is merely not entered yet)
    // is a plain hold, not a tiebreak. The clock comparison stays in
    // MatchTimer.tiebreakReached (no own formula, A4-11).
    final timer = MatchTimer(
      startedAt: startedAt,
      durationSeconds: durationSeconds,
      tiebreakAfterSeconds: tiebreakAfterSeconds,
      now: _nowValue(),
    );
    final isTiebreak = timer.tiebreakReached;
    final message =
        isTiebreak ? l.tournamentRoundTiebreakHold : l.tournamentRoundHold;

    return Column(
      key: const ValueKey('round-hold'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The frozen clock: MatchCountdown with onHold freezes the remaining
        // time at the match end (A4-11 — no own remaining-time formula).
        MatchCountdown(
          startedAt: startedAt,
          durationSeconds: durationSeconds,
          tiebreakAfterSeconds: tiebreakAfterSeconds,
          serverOffset: serverOffset,
          onHold: true,
          ticker: ticker,
          haptics: haptics,
          now: now,
        ),
        const SizedBox(height: KubbTokens.space2),
        Container(
          padding: const EdgeInsets.all(KubbTokens.space3),
          decoration: BoxDecoration(
            color: KubbTokens.wood400.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
            border: Border.all(color: KubbTokens.wood400),
          ),
          child: Row(children: [
            const Icon(Icons.pause_circle_outline, color: KubbTokens.wood400),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: tokens.fg,
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
