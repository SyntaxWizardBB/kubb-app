import 'package:freezed_annotation/freezed_annotation.dart';

part 'team_models.freezed.dart';
part 'team_models.g.dart';

/// Wire model for the `team_get` header block and the rows returned by
/// `team_list_for_caller`. Field names mirror the snake_case keys of the
/// SECURITY DEFINER RPC payloads (`supabase/migrations/20260615000002_*`)
/// via [JsonKey]; Dart-side accessors stay camelCase.
///
/// Contract for T9 (repository): consumers map this wire shape to
/// domain types (`TeamId`, etc.) at the repository boundary.
@freezed
abstract class TeamWire with _$TeamWire {
  const factory TeamWire({
    @JsonKey(name: 'team_id') required String id,
    @JsonKey(name: 'display_name') required String displayName,
    @JsonKey(name: 'league_membership') required String leagueMembership,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'logo_url') String? logoUrl,
    String? country,
    @JsonKey(name: 'dissolved_at') DateTime? dissolvedAt,
  }) = _TeamWire;

  factory TeamWire.fromJson(Map<String, dynamic> json) =>
      _$TeamWireFromJson(json);
}

/// One row of the `pool` array returned by `team_get`. Mirrors the
/// active rows of `public.team_memberships` (rows with `removed_at IS
/// NULL` only — the RPC filters soft-deleted entries before aggregating).
@freezed
abstract class TeamMembershipWire with _$TeamMembershipWire {
  const factory TeamMembershipWire({
    @JsonKey(name: 'membership_id') required String membershipId,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'joined_at') required DateTime joinedAt,
  }) = _TeamMembershipWire;

  factory TeamMembershipWire.fromJson(Map<String, dynamic> json) =>
      _$TeamMembershipWireFromJson(json);
}

/// Wire model for `public.team_invitations` rows. `state` is one of
/// `pending`, `accepted`, `declined`, `revoked` — kept as a raw String
/// to match the CHECK-constraint domain; the repository can lift it to
/// an enum once a domain type lands.
@freezed
abstract class TeamInvitationWire with _$TeamInvitationWire {
  const factory TeamInvitationWire({
    @JsonKey(name: 'invitation_id') required String invitationId,
    @JsonKey(name: 'team_id') required String teamId,
    @JsonKey(name: 'invitee_user_id') required String inviteeUserId,
    required String state,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _TeamInvitationWire;

  factory TeamInvitationWire.fromJson(Map<String, dynamic> json) =>
      _$TeamInvitationWireFromJson(json);
}

/// One row of the `guests` array returned by `team_get`. Mirrors active
/// `public.team_guest_players` rows.
@freezed
abstract class GuestPlayerWire with _$GuestPlayerWire {
  const factory GuestPlayerWire({
    @JsonKey(name: 'guest_id') required String guestId,
    @JsonKey(name: 'display_name') required String displayName,
    @JsonKey(name: 'added_at') required DateTime addedAt,
  }) = _GuestPlayerWire;

  factory GuestPlayerWire.fromJson(Map<String, dynamic> json) =>
      _$GuestPlayerWireFromJson(json);
}
