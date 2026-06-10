// Invite-only Spaßturnier ("auf Einladung") draft + controller logic.
// Covers: toSetupConfig emits invite_only only for a personal tournament,
// fromDetail prefill round-trips the flag, copyWith/==/hashCode include the
// new fields, and the controller setters (setInviteOnly / addInvitee /
// removeInvitee + dedupe) behave per spec.
// ignore_for_file: cascade_invocations
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';

void main() {
  group('TournamentConfigDraft invite-only', () {
    test('toSetupConfig emits invite_only:true only for a personal tournament',
        () {
      const personalInvite =
          TournamentConfigDraft(clubChoiceMade: true, inviteOnly: true);
      expect(personalInvite.toSetupConfig()['invite_only'], true);

      // Defense-in-depth: a club tournament never emits invite_only:true even
      // if the flag stuck around in the draft.
      const clubWithStaleFlag = TournamentConfigDraft(
        clubId: 'club-1',
        clubChoiceMade: true,
        inviteOnly: true,
      );
      expect(clubWithStaleFlag.toSetupConfig()['invite_only'], false);

      const personalNoInvite =
          TournamentConfigDraft(clubChoiceMade: true);
      expect(personalNoInvite.toSetupConfig()['invite_only'], false);
    });

    test('invitedUsers are NOT persisted in the setup map', () {
      const draft = TournamentConfigDraft(
        clubChoiceMade: true,
        inviteOnly: true,
        invitedUsers: [InvitedUser(userId: 'u1', nickname: 'Anna')],
      );
      final setup = draft.toSetupConfig();
      expect(setup.containsKey('invited_users'), isFalse);
      expect(setup['invite_only'], true);
    });

    test('copyWith carries inviteOnly + invitedUsers, == and hashCode reflect '
        'them', () {
      const base = TournamentConfigDraft(clubChoiceMade: true);
      final withInvite = base.copyWith(
        inviteOnly: true,
        invitedUsers: const [InvitedUser(userId: 'u1', nickname: 'Anna')],
      );
      expect(withInvite.inviteOnly, true);
      expect(withInvite.invitedUsers, hasLength(1));
      expect(withInvite == base, isFalse);
      expect(withInvite.hashCode == base.hashCode, isFalse);

      final sameAgain = base.copyWith(
        inviteOnly: true,
        invitedUsers: const [InvitedUser(userId: 'u1', nickname: 'Anna')],
      );
      expect(withInvite == sameAgain, isTrue);
      expect(withInvite.hashCode == sameAgain.hashCode, isTrue);
    });

    test('InvitedUser equality is by (userId, nickname)', () {
      const a = InvitedUser(userId: 'u1', nickname: 'Anna');
      const b = InvitedUser(userId: 'u1', nickname: 'Anna');
      const c = InvitedUser(userId: 'u1', nickname: 'Annika');
      expect(a, b);
      expect(a == c, isFalse);
    });
  });

  group('TournamentConfigController invite-only setters', () {
    late ProviderContainer container;
    late TournamentConfigController controller;

    TournamentConfigDraft state() =>
        container.read(tournamentConfigControllerProvider);

    setUp(() {
      container = ProviderContainer();
      controller = container.read(tournamentConfigControllerProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('setInviteOnly toggles the flag; turning it off clears invitees', () {
      controller.setInviteOnly(true);
      controller.addInvitee(
        const InvitedUser(userId: 'u1', nickname: 'Anna'),
      );
      expect(state().inviteOnly, true);
      expect(state().invitedUsers, hasLength(1));

      controller.setInviteOnly(false);
      expect(state().inviteOnly, false);
      expect(state().invitedUsers, isEmpty);
    });

    test('addInvitee dedupes by userId (no-op on duplicate)', () {
      controller.setInviteOnly(true);
      controller.addInvitee(const InvitedUser(userId: 'u1', nickname: 'Anna'));
      // Same id, different nickname → ignored.
      controller
          .addInvitee(const InvitedUser(userId: 'u1', nickname: 'Anna B.'));
      controller.addInvitee(const InvitedUser(userId: 'u2', nickname: 'Ben'));
      expect(state().invitedUsers.map((u) => u.userId), ['u1', 'u2']);
    });

    test('removeInvitee drops the matching user', () {
      controller.setInviteOnly(true);
      controller.addInvitee(const InvitedUser(userId: 'u1', nickname: 'Anna'));
      controller.addInvitee(const InvitedUser(userId: 'u2', nickname: 'Ben'));
      controller.removeInvitee('u1');
      expect(state().invitedUsers.map((u) => u.userId), ['u2']);
    });

    test('picking a club resets inviteOnly + invitedUsers', () {
      controller.setInviteOnly(true);
      controller.addInvitee(const InvitedUser(userId: 'u1', nickname: 'Anna'));
      controller.setClubId('club-1');
      expect(state().inviteOnly, false);
      expect(state().invitedUsers, isEmpty);
    });
  });
}
