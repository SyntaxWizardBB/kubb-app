// Wire models for the organizer-team RPCs. Plain classes with manual parsing
// (no codegen) — the payloads are small and mirror the snake_case keys returned
// by `organizer_team_list_for_caller` / `organizer_team_get`.

/// Organizer-team header, from an `organizer_team_list_for_caller` row (raw
/// `organizer_teams` row keyed by `id`) or the `organizer_team_get` header
/// block (keyed by `organizer_team_id`).
class OrganizerTeamWire {
  const OrganizerTeamWire({
    required this.id,
    required this.displayName,
    required this.createdAt,
    this.createdBy,
    this.dissolvedAt,
  });

  factory OrganizerTeamWire.fromJson(Map<String, dynamic> json) {
    DateTime ts(Object? v) => DateTime.parse(v! as String).toUtc();
    return OrganizerTeamWire(
      // `organizer_team_list_for_caller` returns `id`; `organizer_team_get`
      // returns `organizer_team_id`.
      id: (json['organizer_team_id'] ?? json['id']) as String,
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

/// One member of a club, from the `members` array of `organizer_team_get`. `roles` is a
/// set drawn from {owner, admin, referee}.
class OrganizerTeamMemberWire {
  const OrganizerTeamMemberWire({
    required this.membershipId,
    required this.userId,
    required this.roles,
    required this.joinedAt,
    this.displayName,
  });

  factory OrganizerTeamMemberWire.fromJson(Map<String, dynamic> json) {
    return OrganizerTeamMemberWire(
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

/// Full club detail: header + members, from `organizer_team_get`.
class OrganizerTeamDetail {
  const OrganizerTeamDetail({required this.club, required this.members});

  factory OrganizerTeamDetail.fromJson(Map<String, dynamic> json) {
    return OrganizerTeamDetail(
      club: OrganizerTeamWire.fromJson(json),
      members: (json['members'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => OrganizerTeamMemberWire.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final OrganizerTeamWire club;
  final List<OrganizerTeamMemberWire> members;
}

/// A pending join request, from `organizer_team_list_join_requests` (manager view).
class OrganizerTeamJoinRequestWire {
  const OrganizerTeamJoinRequestWire({
    required this.requestId,
    required this.userId,
    required this.createdAt,
    this.displayName,
  });

  factory OrganizerTeamJoinRequestWire.fromJson(Map<String, dynamic> json) {
    return OrganizerTeamJoinRequestWire(
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
const teamRoles = <String>[
  'owner',
  'admin',
  'referee',
];
