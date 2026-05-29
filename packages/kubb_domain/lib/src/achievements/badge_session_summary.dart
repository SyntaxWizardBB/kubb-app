import 'package:kubb_domain/src/achievements/badge.dart';
import 'package:kubb_domain/src/achievements/badge_trigger.dart';
import 'package:meta/meta.dart';

/// Aggregate snapshot fed to the badge engine after a training session
/// has been marked completed.
///
/// The summary carries cumulative ("lifetime") counters rather than
/// just the deltas from the session that triggered it. Triggers are
/// monotone over [BadgeTriggerContext], so they only need the most
/// recent snapshot to decide whether a badge has been earned.
/// Assembling the snapshot is the caller's job; the engine itself does
/// no I/O.
///
/// `sourceSessionId` is propagated into [BadgeUnlock.sourceSessionId]
/// so the inventory screen can deep-link back to the run that produced
/// an unlock.
@immutable
class BadgeSessionSummary {
  const BadgeSessionSummary({
    required this.sourceSessionId,
    required this.context,
  });

  /// Id of the just-completed training session. Used purely for
  /// attribution on the persisted [BadgeUnlock] row.
  final String sourceSessionId;

  /// Lifetime aggregate snapshot at the moment the session completed.
  final BadgeTriggerContext context;
}
