import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('assignPitches - range / top-seed-low-number', () {
    const plan = PitchPlan(
      mode: PitchMode.range,
      rangeFrom: 5,
      rangeTo: 8,
      // sortStrategy defaults to topSeedsLowNumbers.
    );

    test('highest-ranked pairing (lowest order) gets the lowest pitch', () {
      // Pass matches deliberately out of rank order to prove sorting.
      final matches = <RoundMatch>[
        const RoundMatch(key: 10, order: 2),
        const RoundMatch(key: 20, order: 0),
        const RoundMatch(key: 30, order: 1),
      ];

      final result = assignPitches(matches, plan);

      expect(result, {20: 5, 30: 6, 10: 7});
    });

    test('assigns distinct pitches to concurrent matches that fit', () {
      final matches = <RoundMatch>[
        const RoundMatch(key: 1, order: 0),
        const RoundMatch(key: 2, order: 1),
        const RoundMatch(key: 3, order: 2),
      ];

      final result = assignPitches(matches, plan);

      expect(result.values.toSet().length, 3, reason: 'pitches are distinct');
      expect(result.values.toSet(), {5, 6, 7});
    });

    test('is deterministic for identical input', () {
      final matches = <RoundMatch>[
        const RoundMatch(key: 1, order: 1),
        const RoundMatch(key: 2, order: 0),
      ];

      expect(assignPitches(matches, plan), assignPitches(matches, plan));
    });

    test('ties on order keep input order', () {
      final matches = <RoundMatch>[
        const RoundMatch(key: 100, order: 1),
        const RoundMatch(key: 200, order: 1),
      ];

      final result = assignPitches(matches, plan);

      expect(result, {100: 5, 200: 6});
    });
  });

  group('assignPitches - manual order', () {
    test('consumes pitches in PitchPlan.order, matches in list order', () {
      const plan = PitchPlan(
        mode: PitchMode.manual,
        numbers: [3, 7, 9],
        order: [9, 3, 7],
        sortStrategy: PitchSortStrategy.manual,
      );
      // availablePitches() -> [9, 3, 7]. Manual strategy does NOT reorder by
      // RoundMatch.order, so the matches are visited as given.
      final matches = <RoundMatch>[
        const RoundMatch(key: 1, order: 5),
        const RoundMatch(key: 2, order: 0),
        const RoundMatch(key: 3, order: 2),
      ];

      final result = assignPitches(matches, plan);

      expect(result, {1: 9, 2: 3, 3: 7});
    });
  });

  group('assignPitches - group-restricted assignment', () {
    const plan = PitchPlan(
      mode: PitchMode.range,
      rangeFrom: 1,
      rangeTo: 6,
      groupAssignment: {
        'A': [1, 2],
        'B': [3, 4],
      },
      sortStrategy: PitchSortStrategy.manual,
    );

    test("a group's matches draw only from that group's pitches", () {
      final matches = <RoundMatch>[
        const RoundMatch(key: 1, order: 0, group: 'A'),
        const RoundMatch(key: 2, order: 1, group: 'A'),
        const RoundMatch(key: 3, order: 0, group: 'B'),
        const RoundMatch(key: 4, order: 1, group: 'B'),
      ];

      final result = assignPitches(matches, plan);

      expect(result, {1: 1, 2: 2, 3: 3, 4: 4});
    });

    test('top-seed ordering applies within each group independently', () {
      const sortedPlan = PitchPlan(
        mode: PitchMode.range,
        rangeFrom: 1,
        rangeTo: 6,
        groupAssignment: {
          'A': [5, 6],
        },
        // topSeedsLowNumbers default.
      );
      final matches = <RoundMatch>[
        const RoundMatch(key: 1, order: 9, group: 'A'),
        const RoundMatch(key: 2, order: 1, group: 'A'),
      ];

      final result = assignPitches(matches, sortedPlan);

      // Stronger pairing (order 1) gets the lower group pitch (5).
      expect(result, {2: 5, 1: 6});
    });

    test('group with no assigned pitches gets no assignment', () {
      final matches = <RoundMatch>[
        const RoundMatch(key: 1, order: 0, group: 'A'),
        const RoundMatch(key: 9, order: 0, group: 'C'), // C not in plan
      ];

      final result = assignPitches(matches, plan);

      expect(result.containsKey(9), isFalse);
      expect(result[1], 1);
    });

    test('group pitches outside the plan-wide range are dropped', () {
      const narrowPlan = PitchPlan(
        mode: PitchMode.range,
        rangeFrom: 1,
        rangeTo: 3,
        groupAssignment: {
          'A': [2, 99], // 99 is outside 1..3
        },
        sortStrategy: PitchSortStrategy.manual,
      );
      final matches = <RoundMatch>[
        const RoundMatch(key: 1, order: 0, group: 'A'),
        const RoundMatch(key: 2, order: 1, group: 'A'),
      ];

      final result = assignPitches(matches, narrowPlan);

      // Only pitch 2 is valid -> the second match wraps back onto pitch 2.
      expect(result, {1: 2, 2: 2});
    });
  });

  group('assignPitches - more matches than pitches (wrap)', () {
    test('round-robin wraps deterministically onto the front pitches', () {
      const plan = PitchPlan(
        mode: PitchMode.range,
        rangeFrom: 1,
        rangeTo: 2,
        sortStrategy: PitchSortStrategy.manual,
      );
      final matches = <RoundMatch>[
        const RoundMatch(key: 1, order: 0),
        const RoundMatch(key: 2, order: 1),
        const RoundMatch(key: 3, order: 2),
        const RoundMatch(key: 4, order: 3),
        const RoundMatch(key: 5, order: 4),
      ];

      final result = assignPitches(matches, plan);

      // i % 2: pitch[0]=1, pitch[1]=2, wrap...
      expect(result, {1: 1, 2: 2, 3: 1, 4: 2, 5: 1});
    });
  });

  group('assignPitches - empty plan / empty matches', () {
    test('empty available pitches yields no assignment', () {
      const emptyPlan = PitchPlan(mode: PitchMode.manual);
      final matches = <RoundMatch>[
        const RoundMatch(key: 1, order: 0),
        const RoundMatch(key: 2, order: 1),
      ];

      expect(assignPitches(matches, emptyPlan), isEmpty);
    });

    test('range plan without bounds yields no assignment', () {
      const emptyRange = PitchPlan(mode: PitchMode.range);
      final matches = <RoundMatch>[const RoundMatch(key: 1, order: 0)];

      expect(assignPitches(matches, emptyRange), isEmpty);
    });

    test('empty match list yields an empty map', () {
      const plan = PitchPlan(mode: PitchMode.range, rangeFrom: 1, rangeTo: 4);

      expect(assignPitches(const <RoundMatch>[], plan), isEmpty);
    });
  });

  group('RoundMatch value semantics', () {
    test('equality and hashCode are by value', () {
      const a = RoundMatch(key: 1, order: 2, group: 'A');
      const b = RoundMatch(key: 1, order: 2, group: 'A');
      const c = RoundMatch(key: 1, order: 2);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
