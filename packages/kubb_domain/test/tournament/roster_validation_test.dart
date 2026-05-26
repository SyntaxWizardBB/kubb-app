import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Valid roster slot index range per FR-REG, architecture §3.5.
/// T11 mirrors T3's constants intentionally — both files stay independent.
const int _minSlot = 1;
const int _maxSlot = 6;

extension _RosterValidationAnys on Any {
  Generator<int> get validSlotIndex => intInRange(_minSlot, _maxSlot);

  Generator<int> get outOfRangeSlotIndex =>
      choose<int>(const [-10, -1, 0, 7, 8, 12, 100]);

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
  group('FR-REG-12 validator — requireAtLeastOneMember (property)', () {
    Glados<List<RosterSlotInput>>(any.nonEmptyList(any.memberSlotInput)).test(
      'returns true for any non-empty all-member list',
      (slots) => expect(requireAtLeastOneMember(slots), isTrue),
    );

    Glados<List<RosterSlotInput>>(any.nonEmptyList(any.guestSlotInput)).test(
      'returns true iff some entry is a member — pure guest list ⇒ false',
      (slots) => expect(requireAtLeastOneMember(slots), isFalse),
    );

    Glados2<List<RosterSlotInput>, RosterSlotInput>(
      any.listWithLengthInRange(0, 5, any.guestSlotInput),
      any.memberSlotInput,
    ).test('mixed list with at least one member ⇒ true', (guests, member) {
      final mixed = <RosterSlotInput>[...guests, member];
      expect(requireAtLeastOneMember(mixed), isTrue);
    });

    test('empty list ⇒ false', () {
      expect(requireAtLeastOneMember(const <RosterSlotInput>[]), isFalse);
    });
  });

  group('Slot-Index-Range', () {
    for (var n = _minSlot; n <= _maxSlot; n++) {
      test('slotIndex $n is accepted by member ctor', () {
        expect(
          RosterSlotInput.member(n, const UserId('u1')).slotIndex,
          equals(n),
        );
      });
      test('slotIndex $n is accepted by guest ctor', () {
        expect(
          RosterSlotInput.guest(n, TeamGuestPlayerId('g1')).slotIndex,
          equals(n),
        );
      });
    }

    Glados<int>(any.outOfRangeSlotIndex)
        .test('out-of-range index fails member ctor', (idx) {
      expect(
        () => RosterSlotInput.member(idx, const UserId('u1')),
        throwsArgumentError,
      );
    });

    Glados<int>(any.outOfRangeSlotIndex)
        .test('out-of-range index fails guest ctor', (idx) {
      expect(
        () => RosterSlotInput.guest(idx, TeamGuestPlayerId('g1')),
        throwsArgumentError,
      );
    });
  });

  group('validateRosterSlots — duplicate slot index', () {
    test('throws DuplicateSlotIndex for two members sharing slotIndex', () {
      final list = <RosterSlotInput>[
        RosterSlotInput.member(2, const UserId('u1')),
        RosterSlotInput.member(2, const UserId('u2')),
      ];
      expect(
        () => validateRosterSlots(list),
        throwsA(
          isA<DuplicateSlotIndex>().having((e) => e.slotIndex, 'slotIndex', 2),
        ),
      );
    });

    test('throws DuplicateSlotIndex for mixed member/guest collision', () {
      final list = <RosterSlotInput>[
        RosterSlotInput.member(3, const UserId('u1')),
        RosterSlotInput.guest(3, TeamGuestPlayerId('g1')),
      ];
      expect(() => validateRosterSlots(list), throwsA(isA<DuplicateSlotIndex>()));
    });

    test('accepts list with unique slot indices', () {
      final list = <RosterSlotInput>[
        RosterSlotInput.member(1, const UserId('u1')),
        RosterSlotInput.guest(2, TeamGuestPlayerId('g1')),
        RosterSlotInput.member(6, const UserId('u2')),
      ];
      expect(() => validateRosterSlots(list), returnsNormally);
    });

    test('accepts empty list', () {
      expect(
        () => validateRosterSlots(const <RosterSlotInput>[]),
        returnsNormally,
      );
    });
  });
}
