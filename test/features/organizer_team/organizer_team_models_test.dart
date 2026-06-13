import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/organizer_team/data/organizer_team_models.dart';

void main() {
  group('teamRoles (role consolidation, ADR-0032 P1-C)', () {
    test('contains exactly owner, admin, referee in display order', () {
      expect(teamRoles, equals(const ['owner', 'admin', 'referee']));
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
        expect(teamRoles, isNot(contains(role)));
      }
    });
  });
}
