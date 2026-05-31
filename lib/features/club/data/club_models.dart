// Wire models for the club RPCs. Plain classes with manual parsing (no
// codegen) — the payloads are small and mirror the snake_case keys returned
// by `club_list_for_caller` / `club_get` (migration 20260901000013).

/// Club header, from a `club_list_for_caller` row (raw `clubs` row keyed by
/// `id`) or the `club_get` header block (keyed by `club_id`).
class ClubWire {
  const ClubWire({
    required this.id,
    required this.displayName,
    required this.createdAt,
    this.createdBy,
    this.dissolvedAt,
  });

  factory ClubWire.fromJson(Map<String, dynamic> json) {
    DateTime ts(Object? v) => DateTime.parse(v! as String).toUtc();
    return ClubWire(
      // `club_list_for_caller` returns `id`; `club_get` returns `club_id`.
      id: (json['club_id'] ?? json['id']) as String,
      displayName: json['display_name'] as String,
      createdBy: json['created_by'] as String?,
      dissolvedAt: json['dissolved_at'] == null
          ? null
          : ts(json['dissolved_at']),
      createdAt: ts(json['created_at']),
    );
  }

  final String id;
  final String displayName;
  final String? createdBy;
  final DateTime? dissolvedAt;
  final DateTime createdAt;
}

/// One member of a club, from the `members` array of `club_get`. `roles` is a
/// set drawn from {owner, admin, member, referee, timemaster, organizer,
/// scorekeeper, treasurer}.
class ClubMemberWire {
  const ClubMemberWire({
    required this.membershipId,
    required this.userId,
    required this.roles,
    required this.joinedAt,
    this.displayName,
  });

  factory ClubMemberWire.fromJson(Map<String, dynamic> json) {
    return ClubMemberWire(
      membershipId: json['membership_id'] as String,
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String?,
      roles: (json['roles'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e as String)
          .toList(growable: false),
      joinedAt: DateTime.parse(json['joined_at'] as String).toUtc(),
    );
  }

  final String membershipId;
  final String userId;
  final String? displayName;
  final List<String> roles;
  final DateTime joinedAt;

  bool get isManager => roles.contains('owner') || roles.contains('admin');
}

/// Full club detail: header + members, from `club_get`.
class ClubDetail {
  const ClubDetail({required this.club, required this.members});

  factory ClubDetail.fromJson(Map<String, dynamic> json) {
    return ClubDetail(
      club: ClubWire.fromJson(json),
      members: (json['members'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => ClubMemberWire.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final ClubWire club;
  final List<ClubMemberWire> members;
}

/// A pending join request, from `club_list_join_requests` (manager view).
class ClubJoinRequestWire {
  const ClubJoinRequestWire({
    required this.requestId,
    required this.userId,
    required this.createdAt,
    this.displayName,
  });

  factory ClubJoinRequestWire.fromJson(Map<String, dynamic> json) {
    return ClubJoinRequestWire(
      requestId: json['request_id'] as String,
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    );
  }

  final String requestId;
  final String userId;
  final String? displayName;
  final DateTime createdAt;
}

/// The full set of assignable club roles, in display order.
const clubRoles = <String>[
  'owner',
  'admin',
  'member',
  'referee',
  'timemaster',
  'organizer',
  'scorekeeper',
  'treasurer',
];
