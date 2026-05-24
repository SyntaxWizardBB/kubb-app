import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/social/data/group_models.dart';

void main() {
  group('GroupListEntry.fromRow', () {
    test('parses a row with int member_count', () {
      final entry = GroupListEntry.fromRow(<String, dynamic>{
        'group_id': 'g-1',
        'name': 'Sunday Crew',
        'owner_user_id': 'u-1',
        'is_owner': true,
        'member_count': 4,
        'joined_at': '2026-04-12T08:30:00.000Z',
      });

      expect(entry.groupId, 'g-1');
      expect(entry.name, 'Sunday Crew');
      expect(entry.ownerUserId, 'u-1');
      expect(entry.isOwner, isTrue);
      expect(entry.memberCount, 4);
      expect(entry.joinedAt, DateTime.utc(2026, 4, 12, 8, 30));
    });

    test('coerces num member_count to int', () {
      final entry = GroupListEntry.fromRow(<String, dynamic>{
        'group_id': 'g-2',
        'name': 'Trainees',
        'owner_user_id': 'u-2',
        'is_owner': false,
        'member_count': 3.0,
        'joined_at': '2026-04-12T08:30:00.000Z',
      });

      expect(entry.memberCount, 3);
    });

    test('coerces string member_count to int', () {
      final entry = GroupListEntry.fromRow(<String, dynamic>{
        'group_id': 'g-3',
        'name': 'Tournament Buddies',
        'owner_user_id': 'u-3',
        'is_owner': false,
        'member_count': '7',
        'joined_at': '2026-04-12T08:30:00.000Z',
      });

      expect(entry.memberCount, 7);
    });
  });

  group('GroupMember.fromRow', () {
    test('parses a row and exposes raw role string', () {
      final member = GroupMember.fromRow(<String, dynamic>{
        'user_id': 'u-9',
        'nickname': 'Sina',
        'role': 'member',
        'joined_at': '2026-04-12T08:30:00.000Z',
      });

      expect(member.userId, 'u-9');
      expect(member.nickname, 'Sina');
      expect(member.role, 'member');
      expect(member.joinedAt, DateTime.utc(2026, 4, 12, 8, 30));
    });
  });

  group('GroupMember.isOwner', () {
    test('is true only when role is owner', () {
      final owner = GroupMember(
        userId: 'u-1',
        nickname: 'O',
        role: 'owner',
        joinedAt: DateTime.utc(2026, 4, 12),
      );
      final member = GroupMember(
        userId: 'u-2',
        nickname: 'M',
        role: 'member',
        joinedAt: DateTime.utc(2026, 4, 12),
      );

      expect(owner.isOwner, isTrue);
      expect(member.isOwner, isFalse);
    });
  });
}
