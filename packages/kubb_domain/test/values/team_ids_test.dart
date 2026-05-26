import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('TeamGuestPlayerId', () {
    test('wraps a non-empty value', () {
      final id = TeamGuestPlayerId('a1b2c3');
      expect(id.value, equals('a1b2c3'));
    });

    test('equality and hashCode for equal values', () {
      final a = TeamGuestPlayerId('uuid-1');
      final b = TeamGuestPlayerId('uuid-1');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality for different values', () {
      expect(TeamGuestPlayerId('x'), isNot(equals(TeamGuestPlayerId('y'))));
    });

    test('throws ArgumentError on empty string', () {
      expect(() => TeamGuestPlayerId(''), throwsArgumentError);
    });

    test('toString includes type tag', () {
      expect(TeamGuestPlayerId('u').toString(), equals('TeamGuestPlayerId(u)'));
    });
  });

  group('TeamMembershipId', () {
    test('wraps a non-empty value', () {
      final id = TeamMembershipId('a1b2c3');
      expect(id.value, equals('a1b2c3'));
    });

    test('equality and hashCode for equal values', () {
      final a = TeamMembershipId('uuid-2');
      final b = TeamMembershipId('uuid-2');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality for different values', () {
      expect(TeamMembershipId('x'), isNot(equals(TeamMembershipId('y'))));
    });

    test('throws ArgumentError on empty string', () {
      expect(() => TeamMembershipId(''), throwsArgumentError);
    });

    test('toString includes type tag', () {
      expect(TeamMembershipId('u').toString(), equals('TeamMembershipId(u)'));
    });
  });

  group('TeamInvitationId', () {
    test('wraps a non-empty value', () {
      final id = TeamInvitationId('a1b2c3');
      expect(id.value, equals('a1b2c3'));
    });

    test('equality and hashCode for equal values', () {
      final a = TeamInvitationId('uuid-3');
      final b = TeamInvitationId('uuid-3');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality for different values', () {
      expect(TeamInvitationId('x'), isNot(equals(TeamInvitationId('y'))));
    });

    test('throws ArgumentError on empty string', () {
      expect(() => TeamInvitationId(''), throwsArgumentError);
    });

    test('toString includes type tag', () {
      expect(TeamInvitationId('u').toString(), equals('TeamInvitationId(u)'));
    });
  });

  group('cross-type distinction', () {
    test('different ID types with same value are not equal', () {
      expect(
        TeamGuestPlayerId('same-uuid'),
        isNot(equals(TeamMembershipId('same-uuid'))),
      );
      expect(
        TeamMembershipId('same-uuid'),
        isNot(equals(TeamInvitationId('same-uuid'))),
      );
    });
  });
}
