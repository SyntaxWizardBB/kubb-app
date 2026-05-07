/// Compact list-row form returned by `group_list_for_caller`.
class GroupListEntry {
  const GroupListEntry({
    required this.groupId,
    required this.name,
    required this.ownerUserId,
    required this.isOwner,
    required this.memberCount,
    required this.joinedAt,
  });

  factory GroupListEntry.fromRow(Map<String, dynamic> row) {
    // PostgREST sometimes serialises Postgres int as `num` (or even
    // `String` when transiting via certain network paths). Coerce
    // through `num` so a tightly-typed `as int` cast can never throw
    // mid-list-parse and turn the screen into the error branch.
    final memberCountRaw = row['member_count'];
    final memberCount = memberCountRaw is int
        ? memberCountRaw
        : (memberCountRaw is num
            ? memberCountRaw.toInt()
            : int.parse(memberCountRaw.toString()));
    return GroupListEntry(
      groupId: row['group_id'] as String,
      name: row['name'] as String,
      ownerUserId: row['owner_user_id'] as String,
      isOwner: row['is_owner'] as bool,
      memberCount: memberCount,
      joinedAt: DateTime.parse(row['joined_at'] as String),
    );
  }

  final String groupId;
  final String name;
  final String ownerUserId;
  final bool isOwner;
  final int memberCount;
  final DateTime joinedAt;
}

/// One member row, used for the group-detail screen.
class GroupMember {
  const GroupMember({
    required this.userId,
    required this.nickname,
    required this.role,
    required this.joinedAt,
  });

  factory GroupMember.fromRow(Map<String, dynamic> row) {
    return GroupMember(
      userId: row['user_id'] as String,
      nickname: row['nickname'] as String,
      role: row['role'] as String,
      joinedAt: DateTime.parse(row['joined_at'] as String),
    );
  }

  final String userId;
  final String nickname;
  final String role; // 'owner' | 'member'
  final DateTime joinedAt;

  bool get isOwner => role == 'owner';
}
