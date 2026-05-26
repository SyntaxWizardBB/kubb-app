import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Valid roster slot index range per FR-REG, architecture §3.5.
const int _minSlot = 1;
const int _maxSlot = 6;

extension _RosterAnys on Any {
  Generator<int> get validSlotIndex => intInRange(_minSlot, _maxSlot);

  Generator<int> get invalidSlotIndex =>
      choose<int>(const [-1, 0, 7, 8, 100]);

  Generator<UserId> get userId =>
      intInRange(0, 1000).map((n) => UserId('u$n'));

  Generator<TeamGuestPlayerId> get teamGuestPlayerId =>
      intInRange(0, 1000).map((n) => TeamGuestPlayerId('g$n'));

  Generator<RosterSlotInput> get memberSlotInput =>
      combine2<int, UserId, RosterSlotInput>(
        validSlotIndex,
        userId,
        RosterSlotInput.member,
      );

  Generator<RosterSlotInput> get guestSlotInput =>
      combine2<int, TeamGuestPlayerId, RosterSlotInput>(
        validSlotIndex,
        teamGuestPlayerId,
        RosterSlotInput.guest,
      );
}

void main() {
  group('RosterSlotInput.member', () {
    Glados2<int, String>(any.validSlotIndex, any.letterOrDigits)
        .test('sets memberUserId, leaves guestPlayerId null', (idx, raw) {
      final input = RosterSlotInput.member(idx, UserId('u$raw'));
      expect(input.slotIndex, idx);
      expect(input.memberUserId, isNotNull);
      expect(input.memberUserId, equals(UserId('u$raw')));
      expect(input.guestPlayerId, isNull);
    });

    Glados<int>(any.invalidSlotIndex)
        .test('throws ArgumentError on out-of-range slot index', (idx) {
      expect(
        () => RosterSlotInput.member(idx, const UserId('u0')),
        throwsArgumentError,
      );
    });
  });

  group('RosterSlotInput.guest', () {
    Glados2<int, String>(any.validSlotIndex, any.letterOrDigits)
        .test('sets guestPlayerId, leaves memberUserId null', (idx, raw) {
      final input = RosterSlotInput.guest(idx, TeamGuestPlayerId('g$raw'));
      expect(input.slotIndex, idx);
      expect(input.memberUserId, isNull);
      expect(input.guestPlayerId, isNotNull);
      expect(input.guestPlayerId, equals(TeamGuestPlayerId('g$raw')));
    });

    Glados<int>(any.invalidSlotIndex)
        .test('throws ArgumentError on out-of-range slot index', (idx) {
      expect(
        () => RosterSlotInput.guest(idx, TeamGuestPlayerId('g0')),
        throwsArgumentError,
      );
    });
  });

  group('RosterSlotInput invariants', () {
    test('exactly one of memberUserId / guestPlayerId is non-null', () {
      final m = RosterSlotInput.member(1, const UserId('u1'));
      final g = RosterSlotInput.guest(2, TeamGuestPlayerId('g1'));
      expect((m.memberUserId == null) ^ (m.guestPlayerId == null), isTrue);
      expect((g.memberUserId == null) ^ (g.guestPlayerId == null), isTrue);
    });
  });

  group('requireAtLeastOneMember (FR-REG-12)', () {
    Glados<List<RosterSlotInput>>(any.nonEmptyList(any.guestSlotInput))
        .test('false when list contains only guest entries', (slots) {
      expect(requireAtLeastOneMember(slots), isFalse);
    });

    Glados2<List<RosterSlotInput>, RosterSlotInput>(
      any.listWithLengthInRange(0, 5, any.guestSlotInput),
      any.memberSlotInput,
    ).test('true when list contains at least one member entry',
        (guests, member) {
      final mixed = <RosterSlotInput>[...guests, member];
      expect(requireAtLeastOneMember(mixed), isTrue);
    });
  });
}
