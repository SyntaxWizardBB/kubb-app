// Tests target the expected T10 controller API. Compile stays red
// until the team-application providers land — see task brief.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/team/application/team_list_provider.dart';
import 'package:kubb_app/features/team/application/team_membership_controller.dart';
import 'package:kubb_app/features/team/data/team_models.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:logging/logging.dart';

/// Minimal stand-in for [TeamRepository]. Only the methods the
/// controller exercises here are wired; the rest falls through to
/// [noSuchMethod] so the surface stays tiny as T10 grows.
class _FakeTeamRepository implements TeamRepository {
  _FakeTeamRepository({
    this.teams = const <TeamWire>[],
    this.throwOnList,
    this.throwOnCreate,
  });

  final List<TeamWire> teams;
  final Exception? throwOnList;
  final Exception? throwOnCreate;
  ({TeamId teamId, UserId inviteeUserId})? lastInvite;

  @override
  Future<List<TeamWire>> listMyTeams() async {
    if (throwOnList != null) throw throwOnList!;
    return teams;
  }

  @override
  Future<TeamId> createTeam({
    required String displayName,
    required LeagueMembership leagueMembership,
    String? logoUrl,
    String? country,
  }) async {
    if (throwOnCreate != null) throw throwOnCreate!;
    return const TeamId('t-new');
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
      createdAt: DateTime.utc(2026, 5),
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
    // Subscribe to the provider so it fully resolves before we inspect.
    final c = _container(repo)
      ..listen<AsyncValue<List<TeamWire>>>(teamListProvider, (_, _) {});
    // Drain the microtask queue twice — once for the listener registration,
    // once for the awaited repository call to surface its exception.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final state = c.read(teamListProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<TeamPermissionException>());
  });

  test('controller.invite forwards team-id and invitee-id to the repository',
      () async {
    final repo = _FakeTeamRepository();
    final c = _container(repo);
    final controller = c.read(teamMembershipControllerProvider.notifier);

    final result = await controller.invite(
      const TeamId('t-1'),
      const UserId('u-2'),
    );

    expect(result, isA<TeamActionSuccess<TeamInvitationId>>());
    expect(repo.lastInvite, isNotNull);
    expect(repo.lastInvite!.teamId, const TeamId('t-1'));
    expect(repo.lastInvite!.inviteeUserId, const UserId('u-2'));
  });

  test('controller.create folds repository exceptions into TeamActionFailure '
      'and logs a PII-free warning', () async {
    final originalLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(() async {
      await sub.cancel();
      Logger.root.level = originalLevel;
    });

    final repo = _FakeTeamRepository(
      throwOnCreate: const TeamPermissionException('not_authenticated'),
    );
    final c = _container(repo);
    final controller = c.read(teamMembershipControllerProvider.notifier);

    final result = await controller.create(
      displayName: 'Hammer-Crew',
      leagueMembership: LeagueMembership.b,
    );

    expect(result, isA<TeamActionFailure<TeamId>>());
    final failure = result as TeamActionFailure<TeamId>;
    expect(failure.error, isA<TeamActionExceptionError>());
    final err = failure.error as TeamActionExceptionError;
    expect(err.rpc, 'team_create');
    expect(err.error, isA<TeamPermissionException>());

    final warnings = records
        .where((r) =>
            r.level == Level.WARNING && r.loggerName == 'team.membership')
        .toList();
    expect(warnings, hasLength(1));
    expect(warnings.single.error, 'rpc=team_create');
    expect(warnings.single.stackTrace, isNotNull);
    // PII guard: the log payload must not leak the user-supplied
    // display name.
    expect(warnings.single.message, isNot(contains('Hammer-Crew')));
    expect(warnings.single.error.toString(), isNot(contains('Hammer-Crew')));
  });
}
