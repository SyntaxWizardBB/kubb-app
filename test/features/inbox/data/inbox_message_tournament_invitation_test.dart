import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';

/// Spaßturnier "auf Einladung": the invite-only tournament invitation ships on
/// the dedicated wire kind 'tournament_invitation' with an action_payload of
/// {tournament_id, invitation_id, tournament_name}. The kind mapping must route
/// it to the dedicated accept/decline panel, and the payload must be readable
/// for the respond call.
void main() {
  group('InboxMessageKind.fromWire tournament_invitation', () {
    test('wire kind maps to tournamentInvitation', () {
      final kind = InboxMessageKind.fromWire('tournament_invitation');
      expect(kind, InboxMessageKind.tournamentInvitation);
    });

    test('full row parses kind + action_payload (tournament_id / '
        'invitation_id / tournament_name)', () {
      final msg = InboxMessage.fromRow(<String, dynamic>{
        'id': 'inv-msg-1',
        'kind': 'tournament_invitation',
        'subject': 'Einladung zum Turnier',
        'body': 'Du wurdest zu „SommerCup" eingeladen.',
        'sent_at': '2026-06-10T09:00:00Z',
        'action_payload': <String, dynamic>{
          'tournament_id': 't-1',
          'invitation_id': 'inv-1',
          'tournament_name': 'SommerCup',
        },
      });

      expect(msg.kind, InboxMessageKind.tournamentInvitation);
      expect(msg.actionPayload?['tournament_id'], 't-1');
      expect(msg.actionPayload?['invitation_id'], 'inv-1');
      expect(msg.actionPayload?['tournament_name'], 'SommerCup');
    });

    test('unknown wire kind still falls back to notice', () {
      expect(
        InboxMessageKind.fromWire('totally_unknown'),
        InboxMessageKind.notice,
      );
    });
  });
}
