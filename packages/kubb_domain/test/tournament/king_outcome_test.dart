import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

import '../_support/king_outcome_stub.dart';

void main() {
  group('KingOutcome', () {
    test('HitBy carries the scoring participant id', () {
      const outcome = KingHitBy(TournamentParticipantId('p1'));
      expect(outcome.participantId, const TournamentParticipantId('p1'));
    });

    test('HitBy value equality holds for the same participant', () {
      const a = KingHitBy(TournamentParticipantId('p1'));
      const b = KingHitBy(TournamentParticipantId('p1'));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('HitBy with different participant is not equal', () {
      const a = KingHitBy(TournamentParticipantId('p1'));
      const b = KingHitBy(TournamentParticipantId('p2'));
      expect(a, isNot(equals(b)));
    });

    test('Missed has a single value-equal instance', () {
      const a = KingMissed();
      const b = KingMissed();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('TimedOut has a single value-equal instance', () {
      const a = KingTimedOut();
      const b = KingTimedOut();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('the three variants are mutually distinct', () {
      const hit = KingHitBy(TournamentParticipantId('p1'));
      const missed = KingMissed();
      const timedOut = KingTimedOut();
      expect(hit, isNot(equals(missed)));
      expect(missed, isNot(equals(timedOut)));
      expect(hit, isNot(equals(timedOut)));
    });

    test('switch on KingOutcome is exhaustive across all three variants', () {
      String label(KingOutcome o) => switch (o) {
            KingHitBy(:final participantId) => 'hit:${participantId.value}',
            KingMissed() => 'missed',
            KingTimedOut() => 'timeout',
          };

      expect(
        label(const KingHitBy(TournamentParticipantId('p7'))),
        equals('hit:p7'),
      );
      expect(label(const KingMissed()), equals('missed'));
      expect(label(const KingTimedOut()), equals('timeout'));
    });
  });
}
