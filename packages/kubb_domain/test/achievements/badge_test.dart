import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Badge value object', () {
    test('two badges with identical fields are equal', () {
      const a = Badge(
        id: 'hits_100',
        displayName: '100 Hits',
        description: 'Erreiche 100 Treffer im Sniper-Modus.',
        rarity: BadgeRarity.common,
        assetKey: 'badges/hits_100.svg',
      );
      const b = Badge(
        id: 'hits_100',
        displayName: '100 Hits',
        description: 'Erreiche 100 Treffer im Sniper-Modus.',
        rarity: BadgeRarity.common,
        assetKey: 'badges/hits_100.svg',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('BadgeCatalog', () {
    test('ships exactly 15 unique badges', () {
      expect(BadgeCatalog.all, hasLength(15));
      final ids = BadgeCatalog.all.map((b) => b.id).toSet();
      expect(ids, hasLength(15), reason: 'badge ids must be unique');
    });

    test('every catalog entry resolves a trigger', () {
      for (final b in BadgeCatalog.all) {
        expect(
          BadgeCatalog.triggerFor(b.id),
          isNotNull,
          reason: 'missing trigger for ${b.id}',
        );
      }
    });

    test('byId returns null for unknown ids', () {
      expect(BadgeCatalog.byId('does_not_exist'), isNull);
    });

    test('evaluate returns the ids that match the context', () {
      final ids = BadgeCatalog.evaluate(
        const BadgeTriggerContext(sniperHits: 1000),
        alreadyUnlocked: const <String>{},
      );
      expect(ids, containsAll(<String>['hits_100', 'hits_1000']));
    });

    test('evaluate skips ids already in alreadyUnlocked', () {
      final ids = BadgeCatalog.evaluate(
        const BadgeTriggerContext(sniperHits: 1000),
        alreadyUnlocked: const <String>{'hits_100'},
      );
      expect(ids, isNot(contains('hits_100')));
      expect(ids, contains('hits_1000'));
    });

    test('evaluate returns empty list when no trigger matches', () {
      final ids = BadgeCatalog.evaluate(
        const BadgeTriggerContext(),
        alreadyUnlocked: const <String>{},
      );
      expect(ids, isEmpty);
    });
  });

  group('Hits100Trigger', () {
    test('99 hits is not enough', () {
      const trigger = Hits100Trigger();
      expect(
        trigger.evaluate(const BadgeTriggerContext(sniperHits: 99)),
        isFalse,
      );
    });

    test('100 hits unlocks the badge', () {
      const trigger = Hits100Trigger();
      expect(
        trigger.evaluate(const BadgeTriggerContext(sniperHits: 100)),
        isTrue,
      );
    });

    test('more than 100 hits stays unlocked (monotone)', () {
      const trigger = Hits100Trigger();
      expect(
        trigger.evaluate(const BadgeTriggerContext(sniperHits: 5000)),
        isTrue,
      );
    });
  });

  group('Top100EloTrigger', () {
    test('unranked (rank 0) does not unlock', () {
      const trigger = Top100EloTrigger();
      expect(
        trigger.evaluate(const BadgeTriggerContext()),
        isFalse,
      );
    });

    test('rank 100 unlocks, rank 101 does not', () {
      const trigger = Top100EloTrigger();
      expect(
        trigger.evaluate(const BadgeTriggerContext(eloRank: 100)),
        isTrue,
      );
      expect(
        trigger.evaluate(const BadgeTriggerContext(eloRank: 101)),
        isFalse,
      );
    });
  });

  group('Streak10Trigger', () {
    test('streak below 10 does not unlock', () {
      const trigger = Streak10Trigger();
      expect(
        trigger.evaluate(const BadgeTriggerContext(sniperMaxStreak: 9)),
        isFalse,
      );
    });

    test('streak of exactly 10 unlocks', () {
      const trigger = Streak10Trigger();
      expect(
        trigger.evaluate(const BadgeTriggerContext(sniperMaxStreak: 10)),
        isTrue,
      );
    });
  });
}
