import 'package:kubb_domain/src/tournament/tournament_points_award.dart';
import 'package:meta/meta.dart';

/// Outcome of one match contributing to a participant's match-point total
/// (ADR-0024 §2: 3-1-0 default, configurable).
enum MatchOutcome { win, draw, loss, bye }

/// One row of a finalised tournament ranking, used as input to the
/// `LeaguePointsEngine` (architecture §3.1).
@immutable
class FinalStandingRow {
  const FinalStandingRow({
    required this.participantId,
    required this.placement,
    required this.outcomes,
    this.leagueId,
  });

  final String participantId;
  final String? leagueId;
  final int placement;
  final List<MatchOutcome> outcomes;
}

/// Configuration for [LeaguePointsEngine.compute] (FR-POINTS-1, ADR-0024).
@immutable
class LeaguePointsConfig {
  const LeaguePointsConfig({
    this.matchPoints = const {
      MatchOutcome.win: 3,
      MatchOutcome.draw: 1,
      MatchOutcome.loss: 0,
      MatchOutcome.bye: 3,
    },
    this.placementBonus = const [],
    this.tournamentFactor = 1.0,
    this.leagueFactor = 1.0,
  });

  /// Match points per outcome (ADR-0024 §2). Default `win=3, draw=1,
  /// loss=0, bye=3` — bye scores the full win-equivalent per
  /// OD-M5-01-Default.
  final Map<MatchOutcome, int> matchPoints;

  /// Stufungs-Bonus by 1-based placement: `placementBonus[0]` is the
  /// bonus for place 1, `placementBonus[1]` for place 2, ... Plätze
  /// jenseits der Listenlänge erhalten Bonus 0.
  final List<int> placementBonus;

  final double tournamentFactor;
  final double leagueFactor;
}

/// Pure-functional Domain-Service that maps a finished tournament's
/// final standings to one [TournamentPointsAward] per participant
/// according to FR-POINTS-1: `final = base * tournamentFactor *
/// leagueFactor`, with `base = sum(matchPoints) + placementBonus`.
///
/// Reine Funktion ohne State. Identischer Input → identischer Output
/// (Determinismus; tasks.md T4 Acceptance §2).
class LeaguePointsEngine {
  const LeaguePointsEngine();

  List<TournamentPointsAward> compute({
    required List<FinalStandingRow> standings,
    required LeaguePointsConfig config,
    String? leagueId,
  }) {
    final tf = config.tournamentFactor;
    final lf = config.leagueFactor;
    return [
      for (final row in standings)
        _award(row, config, leagueId ?? row.leagueId, tf, lf),
    ];
  }

  TournamentPointsAward _award(
    FinalStandingRow row,
    LeaguePointsConfig config,
    String? leagueId,
    double tf,
    double lf,
  ) {
    var matchSum = 0;
    for (final o in row.outcomes) {
      matchSum += config.matchPoints[o] ?? 0;
    }
    final bonus = row.placement >= 1 &&
            row.placement <= config.placementBonus.length
        ? config.placementBonus[row.placement - 1]
        : 0;
    final base = (matchSum + bonus).toDouble();
    final finalPoints = base * tf * lf;
    final breakdown = 'matches=$matchSum + bonus[place ${row.placement}]='
        '$bonus -> base=$base x TF=$tf x LF=$lf = $finalPoints';
    return TournamentPointsAward(
      participantId: row.participantId,
      leagueId: leagueId,
      placement: row.placement,
      basePoints: base,
      finalPoints: finalPoints,
      breakdown: breakdown,
    );
  }
}
