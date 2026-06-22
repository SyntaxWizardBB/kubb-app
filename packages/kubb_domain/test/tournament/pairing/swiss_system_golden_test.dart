import 'package:kubb_domain/src/tournament/pairing.dart';
import 'package:test/test.dart';

import '../golden/sm_einzel_2026_fixture.dart';

// Regression gate per schoch-swiss-pairing-buchholz-spec.md §7.5: replay the
// real SM Einzel 2026 rounds and measure how many of the actual pairings the
// Monrad strategy reproduces.
//
// Start-number source (spec §6.1 key 3 is DEFINED, not proven): kubb.live
// uses an internal seeding/start number that the data does not expose. The
// closest reproducible proxy is the final ranking order — strong players sit
// near the top of any sane seeding, so we feed `smEinzel2026Participants`
// (kubb.live final ranking) as the participant list and let `planRound` use
// each player's index as the stable start number. This is the
// `seedFromStandings`-style stand-in the milestone plan calls for until M3
// ships the real draw seed list.

const _strategy = SwissSystemStrategy();

String _key(String a, String b) => a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

Set<String> _realPairsForRound(int round) => {
      for (final m in smEinzel2026Matches)
        if (!m.isBye && m.roundNumber == round)
          _key(m.participantA, m.participantB!),
    };

List<MatchResult> _matchesBefore(int round) => [
      for (final m in smEinzel2026Matches)
        if (m.roundNumber < round) m,
    ];

PlannedRound _plan(int round) => _strategy.planRound(
      participants: smEinzel2026Participants,
      completedMatches: _matchesBefore(round),
      roundNumber: round,
      tournamentId: 'sm-einzel-2026',
    );

({int hits, int pairs}) _reproductionForRound(int round) {
  final real = _realPairsForRound(round);
  final planned = _plan(round);
  var hits = 0;
  var pairs = 0;
  for (final p in planned.pairings) {
    if (p.isBye) continue;
    pairs++;
    if (real.contains(_key(p.participantA, p.participantB!))) hits++;
  }
  return (hits: hits, pairs: pairs);
}

void main() {
  group('Swiss-System Monrad reproduction vs SM Einzel 2026', () {
    test('overall R2-R8 reproduction is at least 77%', () {
      var hits = 0;
      var pairs = 0;
      for (var round = 2; round <= 8; round++) {
        final r = _reproductionForRound(round);
        hits += r.hits;
        pairs += r.pairs;
      }
      final rate = 100 * hits / pairs;
      expect(
        rate,
        greaterThanOrEqualTo(77),
        reason: 'R2-R8 reproduced $hits/$pairs = ${rate.toStringAsFixed(1)}%',
      );
    });

    test('R3-R8 reproduction is at least 87% (round 2 is ambiguous)', () {
      var hits = 0;
      var pairs = 0;
      for (var round = 3; round <= 8; round++) {
        final r = _reproductionForRound(round);
        hits += r.hits;
        pairs += r.pairs;
      }
      final rate = 100 * hits / pairs;
      expect(
        rate,
        greaterThanOrEqualTo(87),
        reason: 'R3-R8 reproduced $hits/$pairs = ${rate.toStringAsFixed(1)}%',
      );
    });

    test('round 6 reproduces perfectly (36/36)', () {
      final r = _reproductionForRound(6);
      expect(r.pairs, equals(36));
      expect(r.hits, equals(36));
    });

    test('no rematch across all replayed rounds (0 of 288)', () {
      var rematches = 0;
      for (var round = 2; round <= 8; round++) {
        final played = {
          for (final m in _matchesBefore(round))
            if (!m.isBye) _key(m.participantA, m.participantB!),
        };
        final planned = _plan(round);
        for (final p in planned.pairings) {
          if (p.isBye) continue;
          if (played.contains(_key(p.participantA, p.participantB!))) {
            rematches++;
          }
          expect(p.repeated, isFalse, reason: 'round $round forced a rematch');
        }
      }
      expect(rematches, isZero);
    });

    // Sanity check against the wrong pairing rule (spec §7.5): the same
    // standings paired Fold/Dutch (top half vs bottom half) reproduce far
    // worse than Monrad adjacent. This guards against silently regressing
    // into a Dutch pairing.
    test('Monrad beats Fold/Dutch by a wide margin', () {
      var monradHits = 0;
      var foldHits = 0;
      var pairs = 0;

      for (var round = 2; round <= 8; round++) {
        final real = _realPairsForRound(round);
        final planned = _plan(round);
        final order = [
          for (final p in planned.pairings)
            if (!p.isBye) ...[p.participantA, p.participantB!],
        ];
        for (final p in planned.pairings) {
          if (p.isBye) continue;
          if (real.contains(_key(p.participantA, p.participantB!))) monradHits++;
        }

        final half = order.length ~/ 2;
        for (var i = 0; i < half; i++) {
          pairs++;
          if (real.contains(_key(order[i], order[i + half]))) foldHits++;
        }
      }

      final monradRate = 100 * monradHits / pairs;
      final foldRate = 100 * foldHits / pairs;
      expect(
        monradRate - foldRate,
        greaterThan(30),
        reason: 'Monrad ${monradRate.toStringAsFixed(1)}% vs '
            'Fold ${foldRate.toStringAsFixed(1)}%',
      );
    });
  });
}
