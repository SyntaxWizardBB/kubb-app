import 'package:kubb_domain/src/tournament/ekc_score.dart';
import 'package:kubb_domain/src/tournament/pairing/buchholz.dart';
import 'package:kubb_domain/src/tournament/standings.dart';
import 'package:test/test.dart';

MatchEkcScore _winA() => MatchEkcScore([
      SetScore(
        basekubbsKnockedByA: 6,
        basekubbsKnockedByB: 2,
        winner: SetWinner.teamA,
      ),
      SetScore(
        basekubbsKnockedByA: 6,
        basekubbsKnockedByB: 3,
        winner: SetWinner.teamA,
      ),
    ]);

MatchEkcScore _emptyScore() => MatchEkcScore(const []);

TournamentMatchResult _winAOver(String a, String b) => TournamentMatchResult(
      participantA: a,
      participantB: b,
      score: _winA(),
    );

void main() {
  group('BuchholzCalculator', () {
    const calc = BuchholzCalculator();

    test('Buchholz = Sigma der Gegnerscores (Lehrbuchbeispiel)', () {
      // 4-Spieler-Mini-Turnier, 2 Runden:
      // R1: P1>P2, P3>P4
      // R2: P1>P3, P2>P4
      // Gegner-Punkte (totalPoints via TournamentMatchResult.score):
      //   _winA() liefert pointsForA = 6+3 + 6+3 = 18; pointsForB = 2+3 = 5.
      // Punkte pro Spieler:
      //   P1: 18 + 18 = 36 (zwei Siege)
      //   P2: 5 + 18 = 23 (1 Niederlage, 1 Sieg gegen P4)
      //   P3: 18 + 5  = 23
      //   P4: 5  + 5  = 10
      // Buchholz(P1) = score(P2) + score(P3) = 23 + 23 = 46.
      // Buchholz(P4) = score(P3) + score(P2) = 23 + 23 = 46.
      final matches = <TournamentMatchResult>[
        _winAOver('P1', 'P2'),
        _winAOver('P3', 'P4'),
        _winAOver('P1', 'P3'),
        _winAOver('P2', 'P4'),
      ];

      expect(calc.scoreFor('P1', matches), 46);
      expect(calc.scoreFor('P4', matches), 46);
      // P2 hat als Gegner P1 (36) und P4 (10) -> 46.
      expect(calc.scoreFor('P2', matches), 46);
    });

    test('Bye wird mit 0 (kein Gegner) gewichtet', () {
      // P1 hat in R1 einen Bye, in R2 gegen P2 gewonnen.
      // P2 hat in R1 gegen P3 gewonnen, in R2 gegen P1 verloren.
      // Gegnerliste P1 = [P2] -> Buchholz(P1) = score(P2).
      final matches = <TournamentMatchResult>[
        TournamentMatchResult(
          participantA: 'P1',
          participantB: null,
          score: _emptyScore(),
        ),
        _winAOver('P2', 'P3'),
        _winAOver('P1', 'P2'),
      ];

      // P2: 18 (Sieg ueber P3) + 5 (Niederlage gegen P1) = 23.
      // Buchholz(P1) = score(P2) = 23. Der Bye taucht NICHT in der Gegnersumme auf.
      expect(calc.scoreFor('P1', matches), 23);
    });

    test('unbekannte Teilnehmer-ID liefert 0', () {
      // Defensive Auswertung: ein Spieler, der noch keine Matches hatte,
      // hat Buchholz 0 (kein Gegner).
      final matches = <TournamentMatchResult>[
        _winAOver('P1', 'P2'),
      ];
      expect(calc.scoreFor('P3', matches), 0);
    });
  });
}
