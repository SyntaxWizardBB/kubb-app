import 'package:kubb_domain/src/values/ids.dart';
import 'package:meta/meta.dart';

/// Status automaton of one round's schedule row (ADR-0031 §Modell).
///
/// Mirrors EXACTLY the server-side `CHECK (status IN (...))` of the
/// `public.tournament_round_schedule` table (migration
/// `20261251000000_tournament_round_schedule.sql`):
///
///   published -> call -> running -> awaiting_results -> completed
///
/// * [published] — round computed; participants notified ("Runde N, Pitch,
///   Start HH:MM"). The call/pause window has not opened yet.
/// * [call] — call/pause window (`break_seconds`) before play; clients show
///   the "next round in mm:ss" countdown until `starts_at`.
/// * [running] — `starts_at` reached; the match clock runs.
/// * [awaitingResults] — `ends_at` reached but not all matches are terminal
///   (e.g. a tiebreak). The clock HOLDS (pause semantics) until entered.
/// * [completed] — all of the round's matches are terminal; the runner may
///   materialise the next round.
enum RoundStatus {
  published,
  call,
  running,
  awaitingResults,
  completed,
}

/// Immutable read-side snapshot of one `tournament_round_schedule` row
/// (ADR-0031 Block A1/A3c). Pure data — no Flutter/Supabase imports. The
/// data-layer CDC parser fills it in from the raw realtime row; the runner
/// UI reads it to drive the server-/pause-corrected countdown.
///
/// One row per `(tournamentId, roundNumber, stageNodeId)`. [stageNodeId] is
/// `null` for the classic (non-stage-graph) path and otherwise equals
/// `tournament_stages.node_id`.
///
/// Restzeit-Formel (ADR-0031 §Modell — identical on server and client):
/// ```text
/// effective_elapsed = (now - startsAt) - pausedAccumSeconds
///                     - (pausedAt != null ? (now - pausedAt) : 0)
/// remaining         = matchSeconds - effective_elapsed   // < 0 => expired
/// ```
/// where `now` is the skew-corrected server time. [pausedAt] freezes the
/// clock; [pausedAccumSeconds] is credited back on resume. A round in
/// [RoundStatus.awaitingResults] holds the clock at `endsAt`.
@immutable
class TournamentRoundScheduleRef {
  const TournamentRoundScheduleRef({
    required this.tournamentId,
    required this.stageNodeId,
    required this.roundNumber,
    required this.phase,
    required this.status,
    required this.publishedAt,
    required this.startsAt,
    required this.endsAt,
    required this.breakSeconds,
    required this.matchSeconds,
    required this.tiebreakAfterSeconds,
    required this.pausedAt,
    required this.pausedAccumSeconds,
  });

  final TournamentId tournamentId;

  /// `null` for the classic (non-stage-graph) path; otherwise the
  /// `tournament_stages.node_id` this round belongs to.
  final String? stageNodeId;

  /// 1-based round number within the phase.
  final int roundNumber;

  /// Derived phase label: `group` (prelim/group-phase/schoch), `ko`, or
  /// `final`.
  /// Free text on purpose (the server stores it without a CHECK), so future
  /// phases stay additive.
  final String phase;

  final RoundStatus status;

  /// When the round was published / notified.
  final DateTime publishedAt;

  /// `publishedAt + breakSeconds` — when play starts (the match clock anchor).
  final DateTime startsAt;

  /// `startsAt + matchSeconds` — nominal end of the match window.
  final DateTime endsAt;

  /// Call/pause window before play, in seconds (>= 0).
  final int breakSeconds;

  /// Nominal match duration, in seconds (>= 0).
  final int matchSeconds;

  /// Elapsed-seconds offset at which the tiebreak window opens, or `null`
  /// when this phase has no tiebreak configured.
  final int? tiebreakAfterSeconds;

  /// Anchor of the currently-running pause, or `null` when not paused.
  /// While set, the Restzeit-Formel subtracts the live `(now - pausedAt)`
  /// slice and the clock is frozen.
  final DateTime? pausedAt;

  /// Accumulated seconds of all already-finished pauses (>= 0). Subtracted
  /// from the elapsed time so a resumed pause keeps that time off the clock.
  final int pausedAccumSeconds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentRoundScheduleRef &&
          other.tournamentId == tournamentId &&
          other.stageNodeId == stageNodeId &&
          other.roundNumber == roundNumber &&
          other.phase == phase &&
          other.status == status &&
          other.publishedAt == publishedAt &&
          other.startsAt == startsAt &&
          other.endsAt == endsAt &&
          other.breakSeconds == breakSeconds &&
          other.matchSeconds == matchSeconds &&
          other.tiebreakAfterSeconds == tiebreakAfterSeconds &&
          other.pausedAt == pausedAt &&
          other.pausedAccumSeconds == pausedAccumSeconds;

  @override
  int get hashCode => Object.hash(
        tournamentId,
        stageNodeId,
        roundNumber,
        phase,
        status,
        publishedAt,
        startsAt,
        endsAt,
        breakSeconds,
        matchSeconds,
        tiebreakAfterSeconds,
        pausedAt,
        pausedAccumSeconds,
      );
}
