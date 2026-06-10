import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('TournamentAdminCardRef', () {
    TournamentAdminCardRef full() => TournamentAdminCardRef(
          tournamentId: const TournamentId('t1'),
          displayName: 'Spring Cup',
          format: TournamentFormat.swiss,
          status: TournamentStatus.live,
          currentRound: 3,
          scheduleStatus: RoundStatus.running,
          remainingSeconds: 420,
          openMatchCount: 5,
          disputedMatchCount: 1,
          pausedAt: DateTime.utc(2026, 6, 8, 14, 30),
        );

    test('constructs with all fields set', () {
      final card = full();
      expect(card.tournamentId, const TournamentId('t1'));
      expect(card.displayName, 'Spring Cup');
      expect(card.format, TournamentFormat.swiss);
      expect(card.status, TournamentStatus.live);
      expect(card.currentRound, 3);
      expect(card.scheduleStatus, RoundStatus.running);
      expect(card.remainingSeconds, 420);
      expect(card.openMatchCount, 5);
      expect(card.disputedMatchCount, 1);
      expect(card.pausedAt, DateTime.utc(2026, 6, 8, 14, 30));
    });

    test('constructs via the NULL-schedule default path', () {
      // LEFT-JOIN-NULL: a published tournament with no schedule row yet.
      const card = TournamentAdminCardRef(
        tournamentId: TournamentId('t2'),
        displayName: 'Autumn Open',
        format: TournamentFormat.singleElimination,
        status: TournamentStatus.published,
      );
      expect(card.currentRound, isNull);
      expect(card.scheduleStatus, isNull);
      expect(card.remainingSeconds, isNull);
      expect(card.pausedAt, isNull);
      // Counter defaults.
      expect(card.openMatchCount, 0);
      expect(card.disputedMatchCount, 0);
    });

    test('value equality and hashCode hold for identical content', () {
      final a = full();
      final b = full();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality when any field differs', () {
      final base = full();
      expect(
        base,
        isNot(equals(
          TournamentAdminCardRef(
            tournamentId: const TournamentId('t1'),
            displayName: 'Spring Cup',
            format: TournamentFormat.swiss,
            status: TournamentStatus.live,
            currentRound: 3,
            scheduleStatus: RoundStatus.running,
            remainingSeconds: 420,
            openMatchCount: 5,
            disputedMatchCount: 2, // differs
            pausedAt: DateTime.utc(2026, 6, 8, 14, 30),
          ),
        )),
      );
      expect(
        base,
        isNot(equals(
          TournamentAdminCardRef(
            tournamentId: const TournamentId('t1'),
            displayName: 'Spring Cup',
            format: TournamentFormat.swiss,
            status: TournamentStatus.live,
            currentRound: 3,
            scheduleStatus: RoundStatus.call, // differs
            remainingSeconds: 420,
            openMatchCount: 5,
            disputedMatchCount: 1,
            pausedAt: DateTime.utc(2026, 6, 8, 14, 30),
          ),
        )),
      );
    });
  });
}
