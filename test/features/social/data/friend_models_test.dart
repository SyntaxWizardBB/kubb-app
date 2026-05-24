import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/social/data/friend_models.dart';

void main() {
  group('FriendRelationship.fromWire', () {
    test('parses the three known states', () {
      expect(
        FriendRelationship.fromWire('pending_outgoing'),
        FriendRelationship.pendingOutgoing,
      );
      expect(
        FriendRelationship.fromWire('pending_incoming'),
        FriendRelationship.pendingIncoming,
      );
      expect(
        FriendRelationship.fromWire('accepted'),
        FriendRelationship.accepted,
      );
    });

    test('falls back to none for null or unknown raw', () {
      expect(FriendRelationship.fromWire(null), FriendRelationship.none);
      expect(FriendRelationship.fromWire(''), FriendRelationship.none);
      expect(
        FriendRelationship.fromWire('blocked'),
        FriendRelationship.none,
      );
    });
  });

  group('FriendCandidate.fromRow', () {
    test('parses a row with an explicit relationship', () {
      final cand = FriendCandidate.fromRow(<String, dynamic>{
        'user_id': 'u-1',
        'nickname': 'Lukas',
        'relationship': 'accepted',
      });

      expect(cand.userId, 'u-1');
      expect(cand.nickname, 'Lukas');
      expect(cand.relationship, FriendRelationship.accepted);
    });

    test('parses a row with null relationship as none', () {
      final cand = FriendCandidate.fromRow(<String, dynamic>{
        'user_id': 'u-2',
        'nickname': 'Mia',
        'relationship': null,
      });

      expect(cand.relationship, FriendRelationship.none);
    });
  });

  group('FriendEntry.fromRow', () {
    test('parses a row with all fields populated', () {
      final entry = FriendEntry.fromRow(<String, dynamic>{
        'user_id': 'u-9',
        'nickname': 'Sina',
        'status': 'accepted',
        'requested_by': 'u-1',
        'since_at': '2026-05-01T10:00:00.000Z',
      });

      expect(entry.userId, 'u-9');
      expect(entry.nickname, 'Sina');
      expect(entry.status, 'accepted');
      expect(entry.requestedBy, 'u-1');
      expect(entry.sinceAt, DateTime.utc(2026, 5, 1, 10));
    });
  });

  group('FriendEntry status helpers', () {
    final acc = FriendEntry(
      userId: 'u-1',
      nickname: 'A',
      status: 'accepted',
      requestedBy: 'u-1',
      sinceAt: DateTime.utc(2026, 5),
    );
    final pen = FriendEntry(
      userId: 'u-2',
      nickname: 'B',
      status: 'pending',
      requestedBy: 'u-2',
      sinceAt: DateTime.utc(2026, 5),
    );

    test('isAccepted is true only for accepted status', () {
      expect(acc.isAccepted, isTrue);
      expect(pen.isAccepted, isFalse);
    });

    test('isPending is true only for pending status', () {
      expect(pen.isPending, isTrue);
      expect(acc.isPending, isFalse);
    });
  });
}
