// ADR-0032 P2-C — client mirrors of the setup/administer gate split
// (migration 20261281000000).
//
// canManageTournamentClubProvider is the SETUP mirror: club-role half of
// `tournament_caller_can_setup` = exactly {owner, admin}. A referee may
// administer a live tournament but never set one up, so referee-only must
// resolve false here. manageableClubsProvider (the wizard's organizing-club
// picker) applies the same {owner, admin} filter: a referee-only club must
// not be offered.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/organizer_team/application/organizer_team_providers.dart';
import 'package:kubb_app/features/organizer_team/data/organizer_team_models.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _userId = 'user-1';

OrganizerTeamWire _club(String id, String name) =>
    OrganizerTeamWire(id: id, displayName: name, createdAt: DateTime.utc(2026));

OrganizerTeamDetail _detail(OrganizerTeamWire club, List<String> rolesForUser1) {
  return OrganizerTeamDetail(
    club: club,
    members: <OrganizerTeamMemberWire>[
      OrganizerTeamMemberWire(
        membershipId: 'm-${club.id}',
        userId: _userId,
        roles: rolesForUser1,
        joinedAt: DateTime.utc(2026),
      ),
    ],
  );
}

/// Container where the signed-in user is [userId], [organizerTeamListProvider] lists
/// one club per key of [rolesByClubId] and [organizerTeamDetailProvider] resolves
/// each club id to the mapped roles.
ProviderContainer _container({
  required String? userId,
  required Map<String, List<String>> rolesByClubId,
}) {
  final clubs = <String, OrganizerTeamWire>{
    for (final id in rolesByClubId.keys) id: _club(id, 'Club $id'),
  };
  return ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue(userId),
      organizerTeamListProvider.overrideWith((ref) async => clubs.values.toList()),
      organizerTeamDetailProvider.overrideWith((ref, clubId) async {
        final club = clubs[clubId.value]!;
        return _detail(club, rolesByClubId[clubId.value]!);
      }),
    ],
  );
}

/// Reads the setup gate for [clubId] after the async club read settled (the
/// gate watches the FutureProvider synchronously and treats loading as
/// false, so the future must complete first).
Future<bool> _readSetupGate(ProviderContainer c, String clubId) async {
  final sub = c.listen(organizerTeamDetailProvider(OrganizerTeamId(clubId)), (_, _) {});
  addTearDown(sub.close);
  await c.read(organizerTeamDetailProvider(OrganizerTeamId(clubId)).future);
  return c.read(canManageTournamentClubProvider(clubId));
}

void main() {
  group('canManageTournamentClubProvider (setup mirror {owner, admin})', () {
    test('referee-only membership -> false (referee may not set up)',
        () async {
      final c = _container(
        userId: _userId,
        rolesByClubId: {
          'club-1': ['referee'],
        },
      );
      addTearDown(c.dispose);
      expect(await _readSetupGate(c, 'club-1'), isFalse);
    });

    test('owner -> true (positive control)', () async {
      final c = _container(
        userId: _userId,
        rolesByClubId: {
          'club-1': ['owner'],
        },
      );
      addTearDown(c.dispose);
      expect(await _readSetupGate(c, 'club-1'), isTrue);
    });

    test('admin -> true (positive control)', () async {
      final c = _container(
        userId: _userId,
        rolesByClubId: {
          'club-1': ['admin'],
        },
      );
      addTearDown(c.dispose);
      expect(await _readSetupGate(c, 'club-1'), isTrue);
    });

    test('legacy organizer role -> false (dropped by the gate split)',
        () async {
      final c = _container(
        userId: _userId,
        rolesByClubId: {
          'club-1': ['organizer'],
        },
      );
      addTearDown(c.dispose);
      expect(await _readSetupGate(c, 'club-1'), isFalse);
    });

    test('null clubId -> false', () {
      final c = _container(
        userId: _userId,
        rolesByClubId: const {},
      );
      addTearDown(c.dispose);
      expect(c.read(canManageTournamentClubProvider(null)), isFalse);
    });

    test('signed out -> false', () async {
      final c = _container(
        userId: null,
        rolesByClubId: {
          'club-1': ['owner'],
        },
      );
      addTearDown(c.dispose);
      expect(await _readSetupGate(c, 'club-1'), isFalse);
    });
  });

  group('manageableClubsProvider (wizard picker excludes referee)', () {
    test('referee-only club excluded, owner and admin clubs included',
        () async {
      final c = _container(
        userId: _userId,
        rolesByClubId: {
          'club-owner': ['owner'],
          'club-referee': ['referee'],
          'club-admin': ['admin'],
        },
      );
      addTearDown(c.dispose);
      final clubs = await c.read(manageableClubsProvider.future);
      expect(
        clubs.map((club) => club.id),
        unorderedEquals(<String>['club-owner', 'club-admin']),
      );
      expect(
        clubs.map((club) => club.id),
        isNot(contains('club-referee')),
      );
    });

    test('only referee/member memberships -> empty picker', () async {
      final c = _container(
        userId: _userId,
        rolesByClubId: {
          'club-referee': ['referee'],
          'club-member': ['member'],
        },
      );
      addTearDown(c.dispose);
      expect(await c.read(manageableClubsProvider.future), isEmpty);
    });

    test('signed out -> empty picker', () async {
      final c = _container(
        userId: null,
        rolesByClubId: {
          'club-owner': ['owner'],
        },
      );
      addTearDown(c.dispose);
      expect(await c.read(manageableClubsProvider.future), isEmpty);
    });
  });
}
