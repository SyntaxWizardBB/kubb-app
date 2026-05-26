// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'team_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TeamWire _$TeamWireFromJson(Map<String, dynamic> json) => _TeamWire(
  id: json['team_id'] as String,
  displayName: json['display_name'] as String,
  leagueMembership: json['league_membership'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  logoUrl: json['logo_url'] as String?,
  country: json['country'] as String?,
  dissolvedAt: json['dissolved_at'] == null
      ? null
      : DateTime.parse(json['dissolved_at'] as String),
);

Map<String, dynamic> _$TeamWireToJson(_TeamWire instance) => <String, dynamic>{
  'team_id': instance.id,
  'display_name': instance.displayName,
  'league_membership': instance.leagueMembership,
  'created_at': instance.createdAt.toIso8601String(),
  'logo_url': instance.logoUrl,
  'country': instance.country,
  'dissolved_at': instance.dissolvedAt?.toIso8601String(),
};

_TeamMembershipWire _$TeamMembershipWireFromJson(Map<String, dynamic> json) =>
    _TeamMembershipWire(
      membershipId: json['membership_id'] as String,
      userId: json['user_id'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );

Map<String, dynamic> _$TeamMembershipWireToJson(_TeamMembershipWire instance) =>
    <String, dynamic>{
      'membership_id': instance.membershipId,
      'user_id': instance.userId,
      'joined_at': instance.joinedAt.toIso8601String(),
    };

_TeamInvitationWire _$TeamInvitationWireFromJson(Map<String, dynamic> json) =>
    _TeamInvitationWire(
      invitationId: json['invitation_id'] as String,
      teamId: json['team_id'] as String,
      inviteeUserId: json['invitee_user_id'] as String,
      state: json['state'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$TeamInvitationWireToJson(_TeamInvitationWire instance) =>
    <String, dynamic>{
      'invitation_id': instance.invitationId,
      'team_id': instance.teamId,
      'invitee_user_id': instance.inviteeUserId,
      'state': instance.state,
      'created_at': instance.createdAt.toIso8601String(),
    };

_GuestPlayerWire _$GuestPlayerWireFromJson(Map<String, dynamic> json) =>
    _GuestPlayerWire(
      guestId: json['guest_id'] as String,
      displayName: json['display_name'] as String,
      addedAt: DateTime.parse(json['added_at'] as String),
    );

Map<String, dynamic> _$GuestPlayerWireToJson(_GuestPlayerWire instance) =>
    <String, dynamic>{
      'guest_id': instance.guestId,
      'display_name': instance.displayName,
      'added_at': instance.addedAt.toIso8601String(),
    };
