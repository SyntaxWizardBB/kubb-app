import 'package:kubb_domain/src/values/ids.dart';
import 'package:meta/meta.dart';

/// Valid roster slot index range per FR-REG / architecture §3.5.
/// Matches the `slot_index BETWEEN 1 AND 6` CHECK constraint in
/// `tournament_roster_slots`.
const int _minSlotIndex = 1;
const int _maxSlotIndex = 6;

/// Roster slot input — exactly one of [memberUserId] or [guestPlayerId]
/// must be set. Validated server-side as well.
@immutable
class RosterSlotInput {
  RosterSlotInput.member(this.slotIndex, UserId user)
      : memberUserId = user,
        guestPlayerId = null {
    _checkSlotIndex(slotIndex);
  }

  RosterSlotInput.guest(this.slotIndex, TeamGuestPlayerId guest)
      : memberUserId = null,
        guestPlayerId = guest {
    _checkSlotIndex(slotIndex);
  }

  final int slotIndex;
  final UserId? memberUserId;
  final TeamGuestPlayerId? guestPlayerId;

  static void _checkSlotIndex(int slotIndex) {
    if (slotIndex < _minSlotIndex || slotIndex > _maxSlotIndex) {
      throw ArgumentError.value(
        slotIndex,
        'slotIndex',
        'must be in [$_minSlotIndex, $_maxSlotIndex]',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RosterSlotInput &&
          other.slotIndex == slotIndex &&
          other.memberUserId == memberUserId &&
          other.guestPlayerId == guestPlayerId;

  @override
  int get hashCode => Object.hash(slotIndex, memberUserId, guestPlayerId);
}

/// FR-REG-12: a roster registration must contain at least one entry that
/// references a registered user (a member, not a guest).
bool requireAtLeastOneMember(List<RosterSlotInput> list) =>
    list.any((s) => s.memberUserId != null);

/// Read model for an open roster slot. Mirrors a row of
/// `public.tournament_roster_slots` (architecture §3.3): the audit-history
/// fields [replacedAt], [replacedBy], and [reason] are null while the slot
/// is open and populated when a replacement has closed the slot.
@immutable
class RosterSlot {
  const RosterSlot({
    required this.id,
    required this.slotIndex,
    required this.memberUserId,
    required this.guestPlayerId,
    required this.assignedAt,
    required this.assignedBy,
    this.replacedAt,
    this.replacedBy,
    this.reason,
  });

  factory RosterSlot.fromJson(Map<String, dynamic> json) {
    final memberRaw = json['member_user_id'] as String?;
    final guestRaw = json['guest_player_id'] as String?;
    final assignedByRaw = json['assigned_by'] as String?;
    final replacedAtRaw = json['replaced_at'] as String?;
    final replacedByRaw = json['replaced_by'] as String?;
    return RosterSlot(
      id: json['id'] as String,
      slotIndex: (json['slot_index'] as num).toInt(),
      memberUserId: memberRaw == null ? null : UserId(memberRaw),
      guestPlayerId: guestRaw == null ? null : TeamGuestPlayerId(guestRaw),
      assignedAt: DateTime.parse(json['assigned_at'] as String),
      assignedBy: assignedByRaw == null ? null : UserId(assignedByRaw),
      replacedAt: replacedAtRaw == null ? null : DateTime.parse(replacedAtRaw),
      replacedBy: replacedByRaw == null ? null : UserId(replacedByRaw),
      reason: json['reason'] as String?,
    );
  }

  final String id;
  final int slotIndex;
  final UserId? memberUserId;
  final TeamGuestPlayerId? guestPlayerId;
  final DateTime assignedAt;
  final UserId? assignedBy;
  final DateTime? replacedAt;
  final UserId? replacedBy;
  final String? reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RosterSlot &&
          other.id == id &&
          other.slotIndex == slotIndex &&
          other.memberUserId == memberUserId &&
          other.guestPlayerId == guestPlayerId &&
          other.assignedAt == assignedAt &&
          other.assignedBy == assignedBy &&
          other.replacedAt == replacedAt &&
          other.replacedBy == replacedBy &&
          other.reason == reason;

  @override
  int get hashCode => Object.hash(
        id,
        slotIndex,
        memberUserId,
        guestPlayerId,
        assignedAt,
        assignedBy,
        replacedAt,
        replacedBy,
        reason,
      );
}
