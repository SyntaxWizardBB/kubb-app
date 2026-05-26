import 'package:kubb_domain/src/values/ids.dart';
import 'package:meta/meta.dart';

/// Roster slot input — exactly one of [memberUserId] or [guestPlayerId]
/// must be set. Filled in by M3.2-T4; this file is a compile-only stub.
@immutable
class RosterSlotInput {
  // Stub: real implementation lands in M3.2-T4. Parameters intentionally
  // unused so the factory signature matches architecture.md §3.5.
  // ignore: avoid_unused_constructor_parameters
  factory RosterSlotInput.member(int slotIndex, UserId userId) =>
      throw UnimplementedError();
  // Stub: see member() above.
  // ignore: avoid_unused_constructor_parameters
  factory RosterSlotInput.guest(int slotIndex, TeamGuestPlayerId guestId) =>
      throw UnimplementedError();

  int get slotIndex => throw UnimplementedError();
  UserId? get memberUserId => throw UnimplementedError();
  TeamGuestPlayerId? get guestPlayerId => throw UnimplementedError();
}

bool requireAtLeastOneMember(List<RosterSlotInput> list) =>
    throw UnimplementedError();
