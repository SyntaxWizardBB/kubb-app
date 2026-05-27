import 'package:kubb_domain/src/tournament/pairing/buchholz.dart';
import 'package:test/test.dart';

MatchResult _m(
  String a,
  String b,
  int pa,
  int pb,
  int round,
) =>
    MatchResult(
      participantA: a,
      participantB: b,
      pointsA: pa,
      pointsB: pb,
      roundNumber: round,
    );

MatchResult _bye(String a, int round) => MatchResult(
      participantA: a,
      participantB: null,
      pointsA: 3,
      pointsB: 0,
      roundNumber: round,
    );

void main() {
  group('BuchholzCalculator', () {
    const calc = BuchholzCalculator();

    test('sums opponent points across two rounds', () {
      final matches = [
        _m('A', 'B', 3, 0, 1),
        _m('A', 'C', 3, 0, 2),
        _m('B', 'D', 3, 0, 2),
        _m('C', 'D', 3, 0, 1),
      ];
      expect(calc.scoreFor('A', matches), equals(6));
    });

    test('bye opponent contributes nothing', () {
      final matches = [
        _bye('A', 1),
        _m('A', 'B', 3, 0, 2),
      ];
      expect(calc.scoreFor('A', matches), equals(0));
    });

    test('unknown participant scores 0', () {
      expect(calc.scoreFor('X', const []), equals(0));
    });
  });
}
