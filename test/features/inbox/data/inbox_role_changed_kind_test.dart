import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';

// Berechtigungskonzept P7: the new 'club_role_changed' wire kind (emitted by
// organizer_team_set_member_roles) parses to the dedicated enum value and is
// not swallowed by the generic notice fallback.
void main() {
  test('fromWire maps club_role_changed to clubRoleChanged', () {
    expect(
      InboxMessageKind.fromWire('club_role_changed'),
      InboxMessageKind.clubRoleChanged,
    );
  });

  test('unknown kinds still fall back to notice', () {
    expect(InboxMessageKind.fromWire('totally_unknown'),
        InboxMessageKind.notice);
  });
}
