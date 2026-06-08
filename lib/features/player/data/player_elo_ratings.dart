// Data layer of the `player` context: the parsed shape of the rows returned by
// a SELECT on `public.player_ratings` for a single user_id.
//
// Visibility is governed entirely by RLS (migration
// `20261221000000_player_ratings_discipline_rls.sql`), NOT by this client:
//   * a `tournament` row is always returned (public),
//   * a `personal` row is returned ONLY when the viewer is the owner or an
//     accepted friend.
// Therefore [PlayerEloRatings.personal] is non-null exactly when the query
// returned a `personal` row — there is no owner/friend logic here, and there
// must never be one. Source: docs/ELO_RATINGS.md §1/§5/§8.

import 'package:flutter/foundation.dart' show immutable;

/// Public tournament ELO. Drives seeding and the leaderboard.
@immutable
class TournamentElo {
  const TournamentElo({required this.elo, required this.games});

  final int elo;
  final int games;

  /// A player is provisional while they have fewer than 10 rated games in
  /// this discipline (dynamic K-factor anchor). Source: ELO_RATINGS.md §3/§7.
  bool get provisional => games < 10;

  @override
  bool operator ==(Object other) =>
      other is TournamentElo && other.elo == elo && other.games == games;

  @override
  int get hashCode => Object.hash(elo, games);
}

/// Private personal ELO (combines tournament + 1vs1). Only ever present when
/// RLS grants the `personal` row to the viewer. No provisional badge is
/// required by §8; `games` is shown as the games-count caption next to the
/// value.
@immutable
class PersonalElo {
  const PersonalElo({required this.elo, required this.games});

  final int elo;
  final int games;

  @override
  bool operator ==(Object other) =>
      other is PersonalElo && other.elo == elo && other.games == games;

  @override
  int get hashCode => Object.hash(elo, games);
}

/// The two ELO disciplines for one player, both optional.
///
///   * [tournament] == null  → the player has never played a rated game.
///   * [personal] == null    → not visible (RLS) OR never played 1vs1/tournament.
///
/// From the client's point of view these two `personal == null` cases are
/// indistinguishable, and they are meant to stay that way.
@immutable
class PlayerEloRatings {
  const PlayerEloRatings({this.tournament, this.personal});

  /// Maps the raw rows of a `player_ratings` SELECT into the model.
  ///
  /// Switches on `row['discipline']` (`'tournament'` / `'personal'`), parses
  /// `elo`/`games` type-robustly, tolerates missing/null values (defaults to
  /// 0 instead of crashing) and ignores unknown `discipline` values.
  ///
  /// Duplicate rows for the same discipline: the LAST row wins (later rows
  /// overwrite earlier ones).
  factory PlayerEloRatings.fromRows(List<Map<String, dynamic>> rows) {
    TournamentElo? tournament;
    PersonalElo? personal;

    for (final row in rows) {
      final discipline = row['discipline'];
      final elo = _toInt(row['elo']);
      final games = _toInt(row['games']);
      switch (discipline) {
        case 'tournament':
          tournament = TournamentElo(elo: elo, games: games);
        case 'personal':
          personal = PersonalElo(elo: elo, games: games);
        default:
          // Unknown discipline → ignore the row instead of crashing.
          break;
      }
    }

    return PlayerEloRatings(tournament: tournament, personal: personal);
  }

  final TournamentElo? tournament;
  final PersonalElo? personal;

  /// Type-robust int parse: accepts [int], [double]/[num] and numeric strings;
  /// null/missing/unparseable → 0.
  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
