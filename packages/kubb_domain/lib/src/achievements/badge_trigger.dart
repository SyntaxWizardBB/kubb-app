import 'package:kubb_domain/src/achievements/badge_catalog.dart';
import 'package:meta/meta.dart';

/// Aggregate-shaped snapshot fed to a trigger to decide whether the
/// associated badge is now earned.
///
/// All counters are cumulative across the user's lifetime — the
/// evaluator runs after every relevant write and asks each trigger
/// "given this state, are we unlocked?". Triggers are monotone: once
/// they flip to `true` for a context they should stay `true` for any
/// context with greater-or-equal counters. The caller is responsible
/// for de-duplicating against the existing unlock list (the trigger
/// only sees the latest aggregate, not the history).
@immutable
class BadgeTriggerContext {
  const BadgeTriggerContext({
    this.sniperHits = 0,
    this.sniperMaxStreak = 0,
    this.finisseurPenalties = 0,
    this.finisseurSuccesses = 0,
    this.heliHits = 0,
    this.matchesPlayed = 0,
    this.matchesWon = 0,
    this.tournamentWins = 0,
    this.tournamentParticipations = 0,
    this.seasonsParticipated = 0,
    this.friendsCount = 0,
    this.eloRating = 0,
    this.eloRank = 0,
    this.consecutiveDaysActive = 0,
    this.distinctDistances = 0,
  });

  /// Total Sniper-mode hits across all completed sniper sessions.
  final int sniperHits;

  /// Best hit-streak the user has ever produced inside a sniper session.
  final int sniperMaxStreak;

  /// Cumulative penalty-stick hits earned in finisseur sessions.
  final int finisseurPenalties;

  /// Number of completed finisseur sessions that ended in a success.
  final int finisseurSuccesses;

  /// Cumulative heli hits (only counted when heli-tracking is enabled).
  final int heliHits;

  /// Total completed matches.
  final int matchesPlayed;

  /// Total matches the user's team won.
  final int matchesWon;

  /// Tournaments where the user's team finished first.
  final int tournamentWins;

  /// Tournaments the user participated in.
  final int tournamentParticipations;

  /// Distinct league seasons the user took part in.
  final int seasonsParticipated;

  /// Accepted-friend count.
  final int friendsCount;

  /// Current ELO rating.
  final int eloRating;

  /// Current ELO leaderboard rank (1-based, 0 == not ranked).
  final int eloRank;

  /// Longest streak of consecutive days with at least one session.
  final int consecutiveDaysActive;

  /// Number of distinct training distances the user has logged sessions
  /// at (used by the "Konstanz-King" / variety-style badges).
  final int distinctDistances;
}

/// A predicate over [BadgeTriggerContext]. One subclass per catalog
/// entry; the evaluator zips catalog and triggers via
/// [BadgeCatalog.triggerFor].
///
/// Modeled as a base class rather than a typedef so each badge gets a
/// nameable, separately-testable trigger object (and so the catalog
/// can hold them as `const` instances).
// ignore: one_member_abstracts
abstract class BadgeTrigger {
  const BadgeTrigger();

  /// Returns `true` when the badge should be considered earned given
  /// the current aggregate snapshot.
  bool evaluate(BadgeTriggerContext ctx);
}

class Hits100Trigger extends BadgeTrigger {
  const Hits100Trigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) => ctx.sniperHits >= 100;
}

class Hits1000Trigger extends BadgeTrigger {
  const Hits1000Trigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) => ctx.sniperHits >= 1000;
}

class FirstPenaltyKubbTrigger extends BadgeTrigger {
  const FirstPenaltyKubbTrigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) => ctx.finisseurPenalties >= 1;
}

class Streak10Trigger extends BadgeTrigger {
  const Streak10Trigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) => ctx.sniperMaxStreak >= 10;
}

class HeliMasterTrigger extends BadgeTrigger {
  const HeliMasterTrigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) => ctx.heliHits >= 25;
}

class KonstanzKingTrigger extends BadgeTrigger {
  const KonstanzKingTrigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) => ctx.consecutiveDaysActive >= 7;
}

class SeasonParticipantTrigger extends BadgeTrigger {
  const SeasonParticipantTrigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) => ctx.seasonsParticipated >= 1;
}

class Top100EloTrigger extends BadgeTrigger {
  const Top100EloTrigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) =>
      ctx.eloRank > 0 && ctx.eloRank <= 100;
}

class FirstMatchTrigger extends BadgeTrigger {
  const FirstMatchTrigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) => ctx.matchesPlayed >= 1;
}

class Matches50Trigger extends BadgeTrigger {
  const Matches50Trigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) => ctx.matchesPlayed >= 50;
}

class FirstTournamentWinTrigger extends BadgeTrigger {
  const FirstTournamentWinTrigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) => ctx.tournamentWins >= 1;
}

class TournamentVeteranTrigger extends BadgeTrigger {
  const TournamentVeteranTrigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) => ctx.tournamentParticipations >= 5;
}

class FirstFriendTrigger extends BadgeTrigger {
  const FirstFriendTrigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) => ctx.friendsCount >= 1;
}

class FinisseurAceTrigger extends BadgeTrigger {
  const FinisseurAceTrigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) => ctx.finisseurSuccesses >= 10;
}

class DistanceExplorerTrigger extends BadgeTrigger {
  const DistanceExplorerTrigger();
  @override
  bool evaluate(BadgeTriggerContext ctx) => ctx.distinctDistances >= 3;
}
