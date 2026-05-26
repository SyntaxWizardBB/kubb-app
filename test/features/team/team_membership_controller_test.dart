// Tests target the expected T10 controller API. Compile stays red
// until the team-application providers land — see task brief.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/team/application/team_list_provider.dart';
import 'package:kubb_app/features/team/application/team_membership_controller.dart';
import 'package:kubb_app/features/team/data/team_models.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Minimal stand-in for [TeamRepository]. Only the two methods the
/// controller exercises here are wired; the rest falls through to
/// [noSuchMethod] so the surface stays tiny as T10 grows.
class _FakeTeamRepository implements TeamRepository {
  _FakeTeamRepository({this.teams = const <TeamWire>[], this.throwOnList});

  final List<TeamWire> teams;
  final Object? throwOnList;
  ({TeamId teamId, UserId inviteeUserId})? lastInvite;

  @override
  Future<List<TeamWire>> listMyTeams() async {
    if (throwOnList != null) throw throwOnList!;
    return teams;
  }

  @override
  Future<TeamInvitationId> invite(TeamId teamId, UserId inviteeUserId) async {
    lastInvite = (teamId: teamId, inviteeUserId: inviteeUserId);
    return TeamInvitationId('inv-1');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

TeamWire _wire(String id, String name) => TeamWire(
      id: id,
      displayName: name,
      leagueMembership: 'B',
      createdAt: DateTime.utc(2026, 5, 1),
    );

ProviderContainer _container(_FakeTeamRepository repo) {
  final c = ProviderContainer(
    overrides: [teamRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('teamListProvider exposes repository rows as AsyncData', () async {
    final repo = _FakeTeamRepository(
      teams: <TeamWire>[_wire('t-1', 'Hammer-Crew'), _wire('t-2', 'Plank-Squad')],
    );
    final c = _container(repo);

    final teams = await c.read(teamListProvider.future);
    expect(teams, hasLength(2));
    expect(teams.first.displayName, 'Hammer-Crew');
    expect(c.read(teamListProvider), isA<AsyncData<List<TeamWire>>>());
  });

  test('teamListProvider surfaces TeamPermissionException as AsyncError',
      () async {
    final repo = _FakeTeamRepository(
      throwOnList: const TeamPermissionException('not_authenticated'),
    );
    final c = _container(repo);

    await expectLater(
      c.read(teamListProvider.future),
      throwsA(isA<TeamPermissionException>()),
    );
    expect(c.read(teamListProvider), isA<AsyncError<List<TeamWire>>>());
  });

  test('controller.invite forwards team-id and invitee-id to the repository',
      () async {
    final repo = _FakeTeamRepository();
    final c = _container(repo);
    final controller = c.read(teamMembershipControllerProvider.notifier);

    await controller.invite(
      teamId: const TeamId('t-1'),
      inviteeUserId: const UserId('u-2'),
    );

    expect(repo.lastInvite, isNotNull);
    expect(repo.lastInvite!.teamId, const TeamId('t-1'));
    expect(repo.lastInvite!.inviteeUserId, const UserId('u-2'));
  });
}
