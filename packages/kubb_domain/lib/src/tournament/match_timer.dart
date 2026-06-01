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
  const MatchTimer({
    required this.startedAt,
    required int durationSeconds,
    required this.now,
    int? tiebreakAfterSeconds,
  })  : rawDurationSeconds = durationSeconds,
        rawTiebreakAfterSeconds = tiebreakAfterSeconds;

  /// When the match clock started.
  final DateTime startedAt;

  /// The reference "current" time. Passed in; never read from the wall clock.
  final DateTime now;

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

  /// Whole [Duration] the match has been running, clamped to be >= 0 (before
  /// [startedAt] reads as zero).
  Duration get elapsed {
    final raw = now.difference(startedAt);
    return raw.isNegative ? Duration.zero : raw;
  }

  /// Time left until [endsAt], clamped to be >= 0.
  Duration get remaining {
    final raw = endsAt.difference(now);
    return raw.isNegative ? Duration.zero : raw;
  }

  /// True once [now] has reached or passed [endsAt].
  ///
  /// A zero-duration match is expired from its start moment. (When
  /// [durationSeconds] is 0, [endsAt] == [startedAt], so any `now >= startedAt`
  /// is expired.)
  bool get isExpired => !now.isBefore(endsAt);

  /// Fraction of the match elapsed, in `0.0..1.0`.
  ///
  /// 0 before/at start, 1 once expired. A zero-duration match reports 1.0
  /// once started (and 0.0 strictly before start).
  double get fractionElapsed {
    if (durationSeconds == 0) return isExpired ? 1.0 : 0.0;
    final fraction = elapsed.inMicroseconds / endsAt.difference(startedAt).inMicroseconds;
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
          other.tiebreakAfterSeconds == tiebreakAfterSeconds;

  @override
  int get hashCode =>
      Object.hash(startedAt, durationSeconds, now, tiebreakAfterSeconds);
}
