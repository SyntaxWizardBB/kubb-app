import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../_support/tournament_generators.dart';

void main() {
  group('Pool.roundRobin properties', () {
    Glados<List<String>>(any.participantIds(max: 12))
        .test('is deterministic for the same participant list', (ids) {
      final a = Pool.roundRobin(ids);
      final b = Pool.roundRobin(ids);
      expect(a.rounds.length, b.rounds.length);
      for (var r = 0; r < a.rounds.length; r++) {
        expect(
          a.rounds[r].pairings.map((p) => (p.participantA, p.participantB)),
          b.rounds[r].pairings.map((p) => (p.participantA, p.participantB)),
        );
      }
    });

    Glados<List<String>>(any.participantIds(max: 12))
        .test('round count is N for odd N and N-1 for even N', (ids) {
      final pool = Pool.roundRobin(ids);
      final expected = ids.length.isOdd ? ids.length : ids.length - 1;
      expect(pool.rounds, hasLength(expected));
    });

    Glados<List<String>>(any.participantIds(max: 12))
        .test('every unordered pair appears exactly once for even N', (ids) {
      if (ids.length.isOdd) return;
      final pool = Pool.roundRobin(ids);
      final seen = <String>{};
      for (final round in pool.rounds) {
        for (final pairing in round.pairings) {
          final b = pairing.participantB;
          if (b == null) {
            fail('even pool must not contain BYE pairings');
          }
          final key = ([pairing.participantA, b]..sort()).join('|');
          expect(seen.add(key), isTrue, reason: 'duplicate pair $key');
        }
      }
      final expectedPairs = ids.length * (ids.length - 1) ~/ 2;
      expect(seen, hasLength(expectedPairs));
    });

    Glados<List<String>>(any.participantIds(min: 3, max: 11))
        .test('each participant gets exactly one BYE for odd N', (ids) {
      if (ids.length.isEven) return;
      final pool = Pool.roundRobin(ids);
      final byeCounts = <String, int>{for (final id in ids) id: 0};
      for (final round in pool.rounds) {
        for (final pairing in round.pairings) {
          if (pairing.isBye) {
            byeCounts.update(pairing.participantA, (v) => v + 1);
          }
        }
      }
      for (final entry in byeCounts.entries) {
        expect(entry.value, 1, reason: '${entry.key} has ${entry.value} byes');
      }
    });

    Glados<List<String>>(any.participantIds(max: 12))
        .test('no pairing pits a participant against themselves', (ids) {
      final pool = Pool.roundRobin(ids);
      for (final round in pool.rounds) {
        for (final pairing in round.pairings) {
          expect(pairing.participantA, isNot(equals(pairing.participantB)));
        }
      }
    });
  });
}
