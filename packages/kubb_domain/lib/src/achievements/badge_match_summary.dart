import 'package:kubb_domain/src/achievements/badge.dart';
import 'package:kubb_domain/src/achievements/badge_trigger.dart';
import 'package:meta/meta.dart';

/// Aggregate snapshot fed to the badge engine after a multi-player
/// match has been finalized.
///
/// Named `BadgeMatchSummary` to disambiguate from the app-level
/// `MatchSummary` list-view DTO. The two carry different shapes on
/// purpose: this one is a lifetime aggregate fed to triggers, the
/// other is a per-row view-model.
///
/// `sourceMatchId` is propagated into [BadgeUnlock.sourceSessionId] so
/// the inventory screen can attribute the unlock back to the match
/// that earned it.
@immutable
class BadgeMatchSummary {
  const BadgeMatchSummary({
    required this.sourceMatchId,
    required this.context,
  });

  /// Id of the just-finalized match.
  final String sourceMatchId;

  /// Lifetime aggregate snapshot at the moment the match was finalized.
  final BadgeTriggerContext context;
}
