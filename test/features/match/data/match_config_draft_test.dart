import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/match/data/match_config_draft.dart';
import 'package:kubb_app/features/match/data/match_models.dart';

void main() {
  group('TeamSlot.localId', () {
    test('SelfSlot has a stable sentinel id', () {
      expect(const SelfSlot().localId, '__self__');
    });

    test('FriendSlot id includes the user id', () {
      const slot = FriendSlot(userId: 'u-1', nickname: 'Lukas');
      expect(slot.localId, 'friend:u-1');
    });
  });

  group('TeamSlotJson.toRpcArgs', () {
    test('SelfSlot serialises with the caller user id', () {
      final args = const SelfSlot().toRpcArgs('caller-42');
      expect(args, {'kind': 'in_app', 'user_id': 'caller-42'});
    });

    test('SelfSlot throws StateError when caller id is missing', () {
      expect(
        () => const SelfSlot().toRpcArgs(null),
        throwsA(isA<StateError>()),
      );
    });

    test('FriendSlot serialises with the friend user id', () {
      const slot = FriendSlot(userId: 'u-9', nickname: 'Mia');
      expect(slot.toRpcArgs('caller-1'), {
        'kind': 'in_app',
        'user_id': 'u-9',
      });
    });
  });

  group('MatchTeamTag.wireId', () {
    test('maps to canonical A and B labels', () {
      expect(MatchTeamTag.a.wireId, 'A');
      expect(MatchTeamTag.b.wireId, 'B');
    });
  });

  group('MatchConfigDraft', () {
    test('defaults to bo1, wins, empty teams', () {
      const draft = MatchConfigDraft();
      expect(draft.format, MatchFormat.bo1);
      expect(draft.scoring, MatchScoring.wins);
      expect(draft.teamA, isEmpty);
      expect(draft.teamB, isEmpty);
    });

    test('copyWith replaces only provided fields', () {
      const draft = MatchConfigDraft();
      final updated = draft.copyWith(
        format: MatchFormat.bo5,
        teamA: const [SelfSlot()],
      );

      expect(updated.format, MatchFormat.bo5);
      expect(updated.teamA, hasLength(1));
      expect(updated.scoring, MatchScoring.wins);
      expect(updated.teamB, isEmpty);
    });

    test('allSlots yields team A first, then team B', () {
      const draft = MatchConfigDraft(
        teamA: [SelfSlot()],
        teamB: [FriendSlot(userId: 'u-2', nickname: 'B')],
      );

      final ids = draft.allSlots.map((s) => s.localId).toList();
      expect(ids, ['__self__', 'friend:u-2']);
    });

    test('containsSelf reflects presence of SelfSlot in either team', () {
      const withSelf = MatchConfigDraft(teamA: [SelfSlot()]);
      const withoutSelf = MatchConfigDraft(
        teamA: [FriendSlot(userId: 'u-1', nickname: 'A')],
      );
      expect(withSelf.containsSelf, isTrue);
      expect(withoutSelf.containsSelf, isFalse);
    });

    test('teamOf locates a slot in team A or team B, else null', () {
      const self = SelfSlot();
      const friend = FriendSlot(userId: 'u-7', nickname: 'F');
      const draft = MatchConfigDraft(teamA: [self], teamB: [friend]);

      expect(draft.teamOf(self), MatchTeamTag.a);
      expect(draft.teamOf(friend), MatchTeamTag.b);
      expect(
        draft.teamOf(const FriendSlot(userId: 'u-x', nickname: 'X')),
        isNull,
      );
    });
  });

  group('MatchConfigDraft.validate', () {
    test('ok when both teams non-empty and self is on a team', () {
      const draft = MatchConfigDraft(
        teamA: [SelfSlot()],
        teamB: [FriendSlot(userId: 'u-1', nickname: 'F')],
      );
      final result = draft.validate();
      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
    });

    test('flags empty team A', () {
      const draft = MatchConfigDraft(teamB: [SelfSlot()]);
      final result = draft.validate();
      expect(result.isValid, isFalse);
      expect(result.issues.any((i) => i.contains('Team A')), isTrue);
    });

    test('flags empty team B', () {
      const draft = MatchConfigDraft(teamA: [SelfSlot()]);
      final result = draft.validate();
      expect(result.issues.any((i) => i.contains('Team B')), isTrue);
    });

    test('flags missing self when both teams are friend-only', () {
      const draft = MatchConfigDraft(
        teamA: [FriendSlot(userId: 'u-1', nickname: 'A')],
        teamB: [FriendSlot(userId: 'u-2', nickname: 'B')],
      );
      final result = draft.validate();
      expect(result.issues.any((i) => i.contains('selbst')), isTrue);
    });

    test('flags oversized team (more than six slots)', () {
      final oversized = List<TeamSlot>.generate(
        7,
        (i) => FriendSlot(userId: 'u-$i', nickname: 'F$i'),
      );
      final draft = MatchConfigDraft(
        teamA: [const SelfSlot()],
        teamB: oversized,
      );
      final result = draft.validate();
      expect(result.isValid, isFalse);
      expect(result.issues.any((i) => i.contains('Team B')), isTrue);
    });
  });

  group('MatchConfigValidation.ok', () {
    test('is valid and has no issues', () {
      const v = MatchConfigValidation.ok();
      expect(v.isValid, isTrue);
      expect(v.issues, isEmpty);
    });
  });
}
