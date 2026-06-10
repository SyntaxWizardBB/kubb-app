import 'package:meta/meta.dart';

/// Pure, deterministic snapshot of a running match's clock.
///
/// The model never reads the wall clock itself: callers pass the current
/// [now], so the same inputs always yield the same output (testable, and
/// safe to drive from a UI ticker or from realtime events).
///
/// Used by the "TournierStart" flow (spec §"TournierStart"): a match has a
/// [startedAt] timestamp and a time limit ([durationSeconds], derived from
/// `match_format.round_time_seconds`). The UI shows [remaining], flips on
/// [isExpired] to vibrate / show "dein Platz ist da, leg los", and may use
/// [tiebreakReached] to flag "Tiebreak ab jetzt".
@immutable
final class MatchTimer {
  /// Builds a timer snapshot.
  ///
  /// [rawDurationSeconds] and the optional [rawTiebreakAfterSeconds] may be
  /// passed negative; both are clamped to be non-negative when read via
  /// [durationSeconds] / [tiebreakAfterSeconds].
  ///
  /// Pause/hold support (ADR-0031 remaining-time formula):
  /// - [pausedAccumSeconds] is the accumulated seconds of all *finished*
  ///   pauses (subtracted from the elapsed time).
  /// - [pausedAt] is the start of the *current, still-running* pause, if any;
  ///   while set, its `(now - pausedAt)` slice is subtracted on top, which
  ///   neutralises the advance of [now] and freezes [remaining].
  /// - [onHold] is an *end-clamp*, not a mid-run pause: it freezes the clock
  ///   at [endsAt] (e.g. `awaiting_results` / tiebreak), so an expired timer
  ///   stops advancing past its end and stays expired, while a not-yet-expired
  ///   held timer keeps ticking. This matches the runner (ADR-0031 §6), where
  ///   a hold only begins once a round reaches `awaiting_results` (i.e. at or
  ///   after [endsAt]). For a true mid-run freeze, use [pausedAt]. It is kept
  ///   semantically separate from [pausedAt] for the UI.
  ///
  /// With the defaults (`pausedAt: null`, `pausedAccumSeconds: 0`,
  /// `onHold: false`) the timer behaves exactly as it did before this addition.
  const MatchTimer({
    required this.startedAt,
    required int durationSeconds,
    required this.now,
    int? tiebreakAfterSeconds,
    this.pausedAt,
    this.pausedAccumSeconds = 0,
    this.onHold = false,
  })  : rawDurationSeconds = durationSeconds,
        rawTiebreakAfterSeconds = tiebreakAfterSeconds;

  /// When the match clock started.
  final DateTime startedAt;

  /// The reference "current" time. Passed in; never read from the wall clock.
  final DateTime now;

  /// Start of the currently-running pause, or null when not paused. While
  /// non-null, its `(now - pausedAt)` slice is subtracted from the elapsed
  /// time, freezing [remaining] for as long as the pause lasts.
  final DateTime? pausedAt;

  /// Accumulated seconds of all already-finished pauses. Subtracted from the
  /// elapsed time so resuming a pause keeps the previously paused time off the
  /// clock.
  final int pausedAccumSeconds;

  /// Whether the clock is held (e.g. `awaiting_results` / tiebreak).
  ///
  /// Semantically an *end-clamp*, not a mid-run pause: it freezes the elapsed
  /// time at [endsAt] (any overshoot past [endsAt] is subtracted), so an
  /// expired held timer stays expired with `remaining == 0` no matter how far
  /// [now] advances, while a *not-yet-expired* held timer keeps ticking up to
  /// [endsAt]. In the runner a hold only begins at/after [endsAt]
  /// (`awaiting_results`), so this is exactly the held behaviour the UI needs.
  /// For a freeze that takes effect *during* a running match, use [pausedAt].
  /// Tracked separately from [pausedAt] so the UI can distinguish "paused"
  /// from "on hold".
  final bool onHold;

  /// The duration as supplied to the constructor (may be negative). Prefer
  /// the clamped [durationSeconds].
  final int rawDurationSeconds;

  /// The tiebreak offset as supplied to the constructor (may be negative or
  /// null). Prefer the clamped [tiebreakAfterSeconds].
  final int? rawTiebreakAfterSeconds;

  /// Total match time limit in seconds, clamped to be non-negative.
  int get durationSeconds =>
      rawDurationSeconds < 0 ? 0 : rawDurationSeconds;

  /// Elapsed-seconds offset from [startedAt] at which the tiebreak opens
  /// (clamped to be non-negative), or null if this match has no tiebreak
  /// trigger.
  int? get tiebreakAfterSeconds => rawTiebreakAfterSeconds == null
      ? null
      : (rawTiebreakAfterSeconds! < 0 ? 0 : rawTiebreakAfterSeconds!);

  /// The match end moment.
  DateTime get endsAt => startedAt.add(Duration(seconds: durationSeconds));

  /// True while the clock is frozen — either [onHold] or a running pause
  /// ([pausedAt] is set). UI uses this to render a held/paused state.
  bool get isFrozen => onHold || pausedAt != null;

  /// Pause-corrected elapsed time as a [Duration] (may be negative; callers
  /// clamp where needed).
  ///
  /// ADR-0031 formula:
  /// `effective_elapsed = (now - startedAt) - pausedAccumSeconds
  ///   - (pausedAt != null ? (now - pausedAt) : 0)` — plus an [onHold]
  /// end-clamp that subtracts only the overshoot past [endsAt] (it freezes the
  /// clock at the match end, it does NOT pause a still-running match; see
  /// [onHold]).
  Duration get _effectiveElapsed {
    var slice = now.difference(startedAt) -
        Duration(seconds: pausedAccumSeconds);
    if (pausedAt != null) {
      // While paused, subtract the live `(now - pausedAt)` slice. As `now`
      // advances this cancels its own advance, freezing the elapsed time.
      final pausedSlice = now.difference(pausedAt!);
      if (!pausedSlice.isNegative) slice -= pausedSlice;
    }
    if (onHold) {
      // Hold freezes the clock at the match end: subtract any overshoot past
      // [endsAt] so a held, expired timer stops advancing (and a not-yet-
      // expired timer is unaffected, since the overshoot is clamped to >= 0).
      final overshoot = now.difference(endsAt);
      if (!overshoot.isNegative) slice -= overshoot;
    }
    return slice;
  }

  /// Pause-corrected [Duration] the match has been running, clamped to be >= 0
  /// (before [startedAt], or with the pause/hold correction pulling it below
  /// zero, reads as zero).
  Duration get elapsed {
    final raw = _effectiveElapsed;
    return raw.isNegative ? Duration.zero : raw;
  }

  /// Time left until the match end, clamped to be >= 0.
  ///
  /// Equals `durationSeconds - effective_elapsed`; a running pause or [onHold]
  /// freezes this value, a finished pause ([pausedAccumSeconds]) is credited
  /// back to the player.
  Duration get remaining {
    final raw = Duration(seconds: durationSeconds) - _effectiveElapsed;
    return raw.isNegative ? Duration.zero : raw;
  }

  /// True once the pause-corrected elapsed time has reached or passed
  /// [durationSeconds].
  ///
  /// A zero-duration match is expired from its start moment. A pause or
  /// [onHold] never *un*-expires an already-expired timer (the hold slice only
  /// clamps the elapsed time at [durationSeconds], leaving it expired).
  bool get isExpired => _effectiveElapsed >= Duration(seconds: durationSeconds);

  /// Fraction of the match elapsed, in `0.0..1.0`.
  ///
  /// 0 before/at start, 1 once expired. A zero-duration match reports 1.0
  /// once started (and 0.0 strictly before start). Based on the same
  /// pause-corrected elapsed time as [elapsed] / [remaining].
  double get fractionElapsed {
    if (durationSeconds == 0) return isExpired ? 1.0 : 0.0;
    final fraction = elapsed.inMicroseconds /
        Duration(seconds: durationSeconds).inMicroseconds;
    if (fraction <= 0) return 0;
    if (fraction >= 1) return 1;
    return fraction;
  }

  /// The wall-clock moment the tiebreak window opens, or null when this match
  /// has no [tiebreakAfterSeconds] configured.
  DateTime? get tiebreakAt => tiebreakAfterSeconds == null
      ? null
      : startedAt.add(Duration(seconds: tiebreakAfterSeconds!));

  /// True once [now] has reached or passed [tiebreakAt]; always false when no
  /// tiebreak trigger is configured.
  bool get tiebreakReached {
    final at = tiebreakAt;
    if (at == null) return false;
    return !now.isBefore(at);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchTimer &&
          other.startedAt == startedAt &&
          other.durationSeconds == durationSeconds &&
          other.now == now &&
          other.tiebreakAfterSeconds == tiebreakAfterSeconds &&
          other.pausedAt == pausedAt &&
          other.pausedAccumSeconds == pausedAccumSeconds &&
          other.onHold == onHold;

  @override
  int get hashCode => Object.hash(
        startedAt,
        durationSeconds,
        now,
        tiebreakAfterSeconds,
        pausedAt,
        pausedAccumSeconds,
        onHold,
      );
}
