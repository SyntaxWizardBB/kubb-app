import 'package:meta/meta.dart';

/// Result of a single league-points award for one participant of one
/// tournament (architecture §3.1 `LeaguePointsEngine`).
///
/// Append-only ledger entry. The [breakdown] string carries an
/// audit-readable explanation of how [finalPoints] was derived from
/// [basePoints], the tournament factor and the league factor.
@immutable
class TournamentPointsAward {
  const TournamentPointsAward({
    required this.participantId,
    required this.leagueId,
    required this.placement,
    required this.basePoints,
    required this.finalPoints,
    required this.breakdown,
  });

  final String participantId;
  final String? leagueId;
  final int placement;
  final double basePoints;
  final double finalPoints;
  final String breakdown;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentPointsAward &&
          other.participantId == participantId &&
          other.leagueId == leagueId &&
          other.placement == placement &&
          other.basePoints == basePoints &&
          other.finalPoints == finalPoints &&
          other.breakdown == breakdown;

  @override
  int get hashCode => Object.hash(
        participantId,
        leagueId,
        placement,
        basePoints,
        finalPoints,
        breakdown,
      );

  @override
  String toString() =>
      'TournamentPointsAward($participantId, place=$placement, '
      'base=$basePoints, final=$finalPoints)';
}
