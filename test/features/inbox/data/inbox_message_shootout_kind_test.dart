import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';

/// P6 D2b: the shoot-out inbox row ships on the generic 'tournament_round'
/// wire kind but is tagged via action_payload['kind'] == 'shootout'. The kind
/// mapping must disambiguate on the payload, not just the raw wire kind, so it
/// routes to the dedicated shoot-out screen instead of the generic 'notice'.
void main() {
  group('InboxMessageKind.fromWire shoot-out disambiguation', () {
    test('tournament_round + payload kind shootout -> tournamentShootout', () {
      final kind = InboxMessageKind.fromWire(
        'tournament_round',
        actionPayload: const {
          'tournament_id': 't-1',
          'kind': 'shootout',
          'start_rank': 1,
        },
      );
      expect(kind, InboxMessageKind.tournamentShootout);
    });

    test('tournament_round WITHOUT shootout payload is NOT a shoot-out', () {
      final kind = InboxMessageKind.fromWire(
        'tournament_round',
        actionPayload: const {'tournament_id': 't-1', 'phase': 'ko'},
      );
      expect(kind, isNot(InboxMessageKind.tournamentShootout));
    });

    test('tournament_round with no payload falls back to notice', () {
      expect(
        InboxMessageKind.fromWire('tournament_round'),
        InboxMessageKind.notice,
      );
    });

    test('known kinds still map 1:1', () {
      expect(
        InboxMessageKind.fromWire('club_invitation'),
        InboxMessageKind.clubInvitation,
      );
      expect(InboxMessageKind.fromWire('system'), InboxMessageKind.system);
    });

    // N1: tournament-end kind.
    test('tournament_finished -> tournamentFinished', () {
      expect(
        InboxMessageKind.fromWire('tournament_finished'),
        InboxMessageKind.tournamentFinished,
      );
    });

    test('tournament_finished is unaffected by an action_payload kind', () {
      // Only 'tournament_round' is disambiguated on action_payload['kind'];
      // a finished row keeps its own distinct wire kind regardless of payload.
      expect(
        InboxMessageKind.fromWire(
          'tournament_finished',
          actionPayload: const {'tournament_id': 't-1', 'phase': 'finished'},
        ),
        InboxMessageKind.tournamentFinished,
      );
    });

    test('fromRow wires the finished kind and keeps the round-time body', () {
      final msg = InboxMessage.fromRow(<String, dynamic>{
        'id': 'm-fin',
        'kind': 'tournament_finished',
        'subject': 'Turnier beendet',
        'body':
            'Turnier "ProbeCup" ist beendet. Danke fürs Mitspielen! '
                '— Spielzeit 30 min',
        'sent_at': '2026-06-06T10:00:00Z',
        'action_payload': <String, dynamic>{
          'tournament_id': 't-1',
          'phase': 'finished',
        },
      });
      expect(msg.kind, InboxMessageKind.tournamentFinished);
      expect(msg.body, contains('Spielzeit 30 min'));
      expect(msg.awaitsReply, isFalse);
    });

    test('fromRow wires the shoot-out kind via the row action_payload', () {
      final msg = InboxMessage.fromRow(<String, dynamic>{
        'id': 'm-1',
        'kind': 'tournament_round',
        'subject': 'Shoot-Out nötig',
        'body': 'Tragt den Sieger ein.',
        'sent_at': '2026-06-03T10:00:00Z',
        'action_payload': <String, dynamic>{
          'tournament_id': 't-1',
          'kind': 'shootout',
          'start_rank': 2,
        },
      });
      expect(msg.kind, InboxMessageKind.tournamentShootout);
      expect(msg.actionPayload?['start_rank'], 2);
    });
  });
}
