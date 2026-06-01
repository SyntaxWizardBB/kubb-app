import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Drives a periodic callback so the [MatchCountdown] can re-evaluate its
/// [MatchTimer] snapshot once per second. Abstracted behind an interface
/// so widget tests can step time deterministically without real delays
/// (spec "TournierStart", STAGE B requirement: injectable ticker).
abstract class CountdownTicker {
  /// Starts ticking; [onTick] fires on every interval. Calling [start]
  /// twice is a no-op until [stop] runs.
  void start(VoidCallback onTick);

  /// Cancels any pending ticks. Safe to call when not running.
  void stop();
}

/// Production ticker: a one-second [Timer.periodic].
class WallClockCountdownTicker implements CountdownTicker {
  Timer? _timer;

  @override
  void start(VoidCallback onTick) {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => onTick());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Test ticker: tests call [fire] manually to advance the UI clock. Pair
/// with an injected `now` callback so the widget reads a controllable
/// time. No real timers, so `pumpAndSettle` never hangs.
class ManualCountdownTicker implements CountdownTicker {
  VoidCallback? _onTick;

  @override
  void start(VoidCallback onTick) => _onTick = onTick;

  @override
  void stop() => _onTick = null;

  /// Simulates one tick of the periodic timer.
  void fire() => _onTick?.call();
}

/// Vibration sink, injectable so a widget test can assert the haptic
/// fires exactly once at expiry without poking the platform channel.
// ignore: one_member_abstracts — deliberate injection seam for tests.
abstract class CountdownHaptics {
  /// Fired once when the timer crosses [MatchTimer.isExpired].
  void onExpire();
}

/// Production haptics: a single heavy impact via Flutter's built-in
/// [HapticFeedback] (no third-party vibration package, per project rule).
class HapticFeedbackCountdownHaptics implements CountdownHaptics {
  const HapticFeedbackCountdownHaptics();

  @override
  void onExpire() {
    unawaited(HapticFeedback.heavyImpact());
  }
}

/// Live match clock for the "TournierStart" flow.
///
/// Renders the [MatchTimer]'s [MatchTimer.remaining] as `mm:ss` plus a
/// progress bar. Once the clock crosses expiry it fires `haptics.onExpire`
/// exactly once and flips to a call-to-action: in pool play
/// "Zeit abgelaufen — Resultat eintragen", in KO with a tiebreak
/// "Tiebreak — Mighty-Finisher melden".
///
/// The widget never reads the wall clock directly: [now] is supplied (and
/// re-read on every tick), so tests drive it via [ManualCountdownTicker]
/// plus a controllable [now].
class MatchCountdown extends StatefulWidget {
  const MatchCountdown({
    required this.startedAt,
    required this.durationSeconds,
    this.tiebreakAfterSeconds,
    this.ticker,
    this.haptics = const HapticFeedbackCountdownHaptics(),
    this.now,
    super.key,
  });

  /// When the match clock started (match.started_at).
  final DateTime startedAt;

  /// Match time limit (match_format round_time_seconds / time_limit).
  final int durationSeconds;

  /// Optional tiebreak trigger offset. When set and reached, the expiry
  /// state offers the Mighty-Finisher path instead of plain result entry.
  final int? tiebreakAfterSeconds;

  /// Ticker driving the 1s re-evaluation. Defaults to a wall-clock timer;
  /// widget tests inject a [ManualCountdownTicker].
  final CountdownTicker? ticker;

  /// Vibration sink. Defaults to [HapticFeedback.heavyImpact].
  final CountdownHaptics haptics;

  /// Clock source. Defaults to [DateTime.now]; tests inject a controllable
  /// callback so the timer can be stepped without real delays.
  final DateTime Function()? now;

  @override
  State<MatchCountdown> createState() => _MatchCountdownState();
}

class _MatchCountdownState extends State<MatchCountdown> {
  late final CountdownTicker _ticker;
  bool _hasFiredExpiry = false;

  @override
  void initState() {
    super.initState();
    _ticker = widget.ticker ?? WallClockCountdownTicker();
    // Fire the initial expiry check synchronously in case the match is
    // already over when the widget mounts.
    _maybeFireExpiry(_buildTimer());
    _ticker.start(_onTick);
  }

  @override
  void dispose() {
    _ticker.stop();
    super.dispose();
  }

  DateTime _nowValue() => (widget.now ?? DateTime.now)();

  MatchTimer _buildTimer() => MatchTimer(
        startedAt: widget.startedAt,
        durationSeconds: widget.durationSeconds,
        now: _nowValue(),
        tiebreakAfterSeconds: widget.tiebreakAfterSeconds,
      );

  void _onTick() {
    if (!mounted) return;
    setState(() {});
    _maybeFireExpiry(_buildTimer());
  }

  /// Fires the haptic exactly once on the first tick where the timer is
  /// expired. Subsequent ticks are no-ops.
  void _maybeFireExpiry(MatchTimer timer) {
    if (_hasFiredExpiry || !timer.isExpired) return;
    _hasFiredExpiry = true;
    widget.haptics.onExpire();
  }

  String _mmss(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final timer = _buildTimer();

    if (timer.isExpired) {
      return _ExpiredState(
        // KO tiebreak takes precedence: if a tiebreak window is configured
        // the expiry CTA points at the Mighty-Finisher report.
        message: timer.tiebreakAfterSeconds != null
            ? l.tournamentMatchTimerTiebreakCta
            : l.tournamentMatchTimerExpiredCta,
        tokens: tokens,
      );
    }

    final fraction = timer.fractionElapsed;
    // Late in the match the bar warns; tiebreak window tints it amber.
    final barColor = timer.tiebreakReached
        ? KubbTokens.wood400
        : (fraction >= 0.9 ? KubbTokens.miss : KubbTokens.meadow500);

    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: tokens.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l.tournamentMatchTimerLabel,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: tokens.fgMuted)),
            Text(
              _mmss(timer.remaining),
              key: const ValueKey('match-countdown-remaining'),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: tokens.fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space2),
        ClipRRect(
          borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor: tokens.bgSunken,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        if (timer.tiebreakReached) ...[
          const SizedBox(height: KubbTokens.space2),
          Text(l.tournamentMatchTimerTiebreakActive,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: KubbTokens.wood400)),
        ],
      ]),
    );
  }
}

class _ExpiredState extends StatelessWidget {
  const _ExpiredState({required this.message, required this.tokens});

  final String message;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('match-countdown-expired'),
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: KubbTokens.miss.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: KubbTokens.miss),
      ),
      child: Row(children: [
        const Icon(Icons.timer_off_outlined, color: KubbTokens.miss),
        const SizedBox(width: KubbTokens.space3),
        Expanded(
          child: Text(message,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: tokens.fg)),
        ),
      ]),
    );
  }
}
