import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

void main() {
  group('EloParticipant.seedRating', () {
    test('solo uses its single ELO across all modes', () {
      final p = EloParticipant.solo(id: 'p', elo: 1500);
      expect(p.seedRating(TeamRatingMode.sum), 1500);
      expect(p.seedRating(TeamRatingMode.average), 1500);
      expect(p.seedRating(TeamRatingMode.weighted), 1500);
    });

    test('sum aggregates member ELO', () {
      const t = EloParticipant.team(id: 't', memberElos: [1000, 1200, 1300]);
      expect(t.seedRating(TeamRatingMode.sum), 3500);
    });

    test('average aggregates member ELO', () {
      const t = EloParticipant.team(id: 't', memberElos: [1000, 1400]);
      expect(t.seedRating(TeamRatingMode.average), 1200);
    });

    test('weighted applies 2/3 factor for 2-player teams', () {
      const t = EloParticipant.team(id: 't', memberElos: [1200, 1200]);
      // avg 1200 * (2 * 2/3) = 1600
      expect(t.seedRating(TeamRatingMode.weighted), closeTo(1600, 1e-9));
    });

    test('weighted collapses to sum for non-2-player teams', () {
      final solo = EloParticipant.solo(id: 's', elo: 1300);
      const trio = EloParticipant.team(id: 't', memberElos: [1000, 1100, 1200]);
      expect(solo.seedRating(TeamRatingMode.weighted),
          solo.seedRating(TeamRatingMode.sum));
      expect(trio.seedRating(TeamRatingMode.weighted),
          trio.seedRating(TeamRatingMode.sum));
    });

    test('missing member ratings default to 1200', () {
      expect(kEloDefault, 1200);
      const t = EloParticipant.team(id: 't', memberElos: [null, 1300]);
      expect(t.seedRating(TeamRatingMode.sum), 1200 + 1300);
      final solo = EloParticipant.solo(id: 's');
      expect(solo.seedRating(TeamRatingMode.sum), 1200);
    });

    test('hasNoHistory is true only when every member is unrated', () {
      expect(EloParticipant.solo(id: 's').hasNoHistory, isTrue);
      expect(
        const EloParticipant.team(id: 't', memberElos: [null, null]).hasNoHistory,
        isTrue,
      );
      expect(
        const EloParticipant.team(id: 't', memberElos: [null, 1200]).hasNoHistory,
        isFalse,
      );
    });
  });

  group('seedFromElo ordering', () {
    test('higher rating gets the better (lower) seed', () {
      final order = seedFromElo([
        EloParticipant.solo(id: 'low', elo: 1100),
        EloParticipant.solo(id: 'high', elo: 1900),
        EloParticipant.solo(id: 'mid', elo: 1500),
      ]);
      expect(order, ['high', 'mid', 'low']);
    });

    test('team sum can outrank a strong solo', () {
      final order = seedFromElo([
        EloParticipant.solo(id: 'solo', elo: 1900),
        const EloParticipant.team(id: 'team', memberElos: [1000, 1000, 1000]),
      ]);
      // team sum 3000 > solo 1900
      expect(order.first, 'team');
    });

    test('no-history participants sort to the bottom', () {
      final order = seedFromElo([
        EloParticipant.solo(id: 'unrated'), // defaults to 1200, no history
        EloParticipant.solo(id: 'weak', elo: 800),
        EloParticipant.solo(id: 'strong', elo: 1500),
      ]);
      expect(order, ['strong', 'weak', 'unrated']);
    });

    test('seedMapFromElo is 1-based and matches the ordered list', () {
      final participants = [
        EloParticipant.solo(id: 'a', elo: 1100),
        EloParticipant.solo(id: 'b', elo: 1800),
      ];
      final map = seedMapFromElo(participants);
      expect(map, {1: 'b', 2: 'a'});
    });
  });

  group('seedFromElo tie determinism', () {
    test('equal ratings tie-break deterministically and totally', () {
      final participants = [
        for (var i = 0; i < 6; i++) EloParticipant.solo(id: 'p$i', elo: 1200),
      ];
      final a = seedFromElo(participants, randomSeed: 42);
      final b = seedFromElo(participants, randomSeed: 42);
      expect(a, equals(b));
      // total order: every participant present exactly once
      expect(a.toSet(), participants.map((p) => p.id).toSet());
      expect(a.length, participants.length);
    });

    test('different random seeds may produce different tie orderings', () {
      final participants = [
        for (var i = 0; i < 8; i++) EloParticipant.solo(id: 'p$i', elo: 1200),
      ];
      final s1 = seedFromElo(participants, randomSeed: 1);
      final s2 = seedFromElo(participants, randomSeed: 999);
      // Same membership regardless of seed.
      expect(s1.toSet(), equals(s2.toSet()));
    });

    Glados<List<int>>(any.list(any.intInRange(1000, 2000))).test(
        'is stable: two calls on the same input yield identical order',
        (elos) {
      final participants = [
        for (var i = 0; i < elos.length; i++)
          EloParticipant.solo(id: 'p$i', elo: elos[i]),
      ];
      final a = seedFromElo(participants, randomSeed: 17);
      final b = seedFromElo(participants, randomSeed: 17);
      expect(a, equals(b));
      // Always a permutation of the input ids.
      expect(a.length, participants.length);
      expect(a.toSet(), participants.map((p) => p.id).toSet());
    });

    Glados<List<int>>(any.list(any.intInRange(1000, 2000))).test(
        'output is non-increasing in seed rating', (elos) {
      final participants = [
        for (var i = 0; i < elos.length; i++)
          EloParticipant.solo(id: 'p$i', elo: elos[i]),
      ];
      final order = seedFromElo(participants);
      final ratingById = {
        for (final p in participants) p.id: p.seedRating(TeamRatingMode.sum),
      };
      for (var i = 1; i < order.length; i++) {
        expect(
          ratingById[order[i - 1]]! >= ratingById[order[i]]!,
          isTrue,
          reason: 'seed $i must not outrank seed ${i - 1}',
        );
      }
    });
  });
}
