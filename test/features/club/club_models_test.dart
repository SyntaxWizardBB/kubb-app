import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/club/data/club_models.dart';

void main() {
  group('clubRoles (role consolidation, ADR-0032 P1-C)', () {
    test('contains exactly owner, admin, referee in display order', () {
      expect(clubRoles, equals(const ['owner', 'admin', 'referee']));
    });

    test('no longer contains stripped legacy roles', () {
      const stripped = [
        'member',
        'timemaster',
        'organizer',
        'scorekeeper',
        'treasurer',
      ];
      for (final role in stripped) {
        expect(clubRoles, isNot(contains(role)));
      }
    });
  });
}
