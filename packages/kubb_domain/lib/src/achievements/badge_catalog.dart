import 'package:kubb_domain/src/achievements/badge.dart';
import 'package:kubb_domain/src/achievements/badge_trigger.dart';

/// Static catalog of all badges shipped with the app, per AUDIT.md §4.6.
///
/// The list intentionally lives in pure Dart so it can be referenced
/// both by the engine (trigger evaluation) and by tests. Adding a badge
/// is a three-step diff: add the [Badge] entry, add the corresponding
/// [BadgeTrigger] subclass in `badge_trigger.dart`, and wire the two in
/// [BadgeCatalog.triggerFor].
class BadgeCatalog {
  const BadgeCatalog._();

  /// 15 badge definitions covering the AUDIT-suggested spectrum:
  /// volume milestones, finisseur, streaks, heli, league, social, tournament.
  static const List<Badge> all = <Badge>[
    Badge(
      id: 'hits_100',
      displayName: '100 Hits',
      description: 'Erreiche 100 Treffer im Sniper-Modus.',
      rarity: BadgeRarity.common,
      assetKey: 'badges/hits_100.svg',
    ),
    Badge(
      id: 'hits_1000',
      displayName: '1000 Hits',
      description: 'Erreiche 1000 Treffer im Sniper-Modus.',
      rarity: BadgeRarity.rare,
      assetKey: 'badges/hits_1000.svg',
    ),
    Badge(
      id: 'first_penalty_kubb',
      displayName: 'Erster Strafkubb',
      description: 'Triff den ersten Strafkubb in einer Finisseur-Session.',
      rarity: BadgeRarity.common,
      assetKey: 'badges/first_penalty_kubb.svg',
    ),
    Badge(
      id: 'streak_10',
      displayName: '10x Streak',
      description: 'Schaffe 10 Treffer in Folge in einer Session.',
      rarity: BadgeRarity.rare,
      assetKey: 'badges/streak_10.svg',
    ),
    Badge(
      id: 'heli_master',
      displayName: 'Heli-Master',
      description: 'Sammle 25 Heli-Treffer mit aktiviertem Tracking.',
      rarity: BadgeRarity.rare,
      assetKey: 'badges/heli_master.svg',
    ),
    Badge(
      id: 'konstanz_king',
      displayName: 'Konstanz-King',
      description: 'Trainiere 7 Tage in Folge.',
      rarity: BadgeRarity.epic,
      assetKey: 'badges/konstanz_king.svg',
    ),
    Badge(
      id: 'season_participant',
      displayName: 'Saisonteilnehmer',
      description: 'Nimm an einer Liga-Saison teil.',
      rarity: BadgeRarity.common,
      assetKey: 'badges/season_participant.svg',
    ),
    Badge(
      id: 'elo_top_100',
      displayName: 'Top 100 ELO',
      description: 'Stehe auf einem Platz unter den Top 100 im ELO-Ranking.',
      rarity: BadgeRarity.epic,
      assetKey: 'badges/elo_top_100.svg',
    ),
    Badge(
      id: 'first_match',
      displayName: 'Erstes Match',
      description: 'Spiele dein erstes Match.',
      rarity: BadgeRarity.common,
      assetKey: 'badges/first_match.svg',
    ),
    Badge(
      id: 'matches_50',
      displayName: '50 Matches',
      description: 'Spiele insgesamt 50 Matches.',
      rarity: BadgeRarity.rare,
      assetKey: 'badges/matches_50.svg',
    ),
    Badge(
      id: 'first_tournament_win',
      displayName: 'Erster Turniersieg',
      description: 'Gewinne dein erstes Turnier.',
      rarity: BadgeRarity.epic,
      assetKey: 'badges/first_tournament_win.svg',
    ),
    Badge(
      id: 'tournament_veteran',
      displayName: 'Turnier-Veteran',
      description: 'Nimm an 5 Turnieren teil.',
      rarity: BadgeRarity.rare,
      assetKey: 'badges/tournament_veteran.svg',
    ),
    Badge(
      id: 'first_friend',
      displayName: 'Erster Freund',
      description: 'Verbinde dich mit deinem ersten Freund.',
      rarity: BadgeRarity.common,
      assetKey: 'badges/first_friend.svg',
    ),
    Badge(
      id: 'finisseur_ace',
      displayName: 'Finisseur-Ass',
      description: 'Beende 10 erfolgreiche Finisseur-Sessions.',
      rarity: BadgeRarity.rare,
      assetKey: 'badges/finisseur_ace.svg',
    ),
    Badge(
      id: 'distance_explorer',
      displayName: 'Distanz-Entdecker',
      description: 'Trainiere auf mindestens 3 verschiedenen Distanzen.',
      rarity: BadgeRarity.common,
      assetKey: 'badges/distance_explorer.svg',
    ),
  ];

  /// O(n) lookup — fine for n=15 and called at most once per badge eval.
  static Badge? byId(String id) {
    for (final b in all) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Returns the trigger predicate paired with the catalog entry.
  /// Returns `null` for unknown ids so callers can defensively skip.
  static BadgeTrigger? triggerFor(String badgeId) {
    switch (badgeId) {
      case 'hits_100':
        return const Hits100Trigger();
      case 'hits_1000':
        return const Hits1000Trigger();
      case 'first_penalty_kubb':
        return const FirstPenaltyKubbTrigger();
      case 'streak_10':
        return const Streak10Trigger();
      case 'heli_master':
        return const HeliMasterTrigger();
      case 'konstanz_king':
        return const KonstanzKingTrigger();
      case 'season_participant':
        return const SeasonParticipantTrigger();
      case 'elo_top_100':
        return const Top100EloTrigger();
      case 'first_match':
        return const FirstMatchTrigger();
      case 'matches_50':
        return const Matches50Trigger();
      case 'first_tournament_win':
        return const FirstTournamentWinTrigger();
      case 'tournament_veteran':
        return const TournamentVeteranTrigger();
      case 'first_friend':
        return const FirstFriendTrigger();
      case 'finisseur_ace':
        return const FinisseurAceTrigger();
      case 'distance_explorer':
        return const DistanceExplorerTrigger();
      default:
        return null;
    }
  }
}
