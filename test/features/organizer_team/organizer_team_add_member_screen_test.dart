// Widget tests for the club add-member screen's role picker (P3-C):
// the SegmentedButton renders all teamRoles, defaults to 'admin', and the
// selected role reaches the repository's invite call.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/organizer_team/data/organizer_team_repository.dart';
import 'package:kubb_app/features/organizer_team/presentation/organizer_team_add_member_screen.dart';
import 'package:kubb_app/features/social/application/social_providers.dart';
import 'package:kubb_app/features/social/data/friend_models.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Minimal stand-in for [OrganizerTeamRepository]: records the last invite call
/// (including the role); everything else falls through to [noSuchMethod].
class _FakeClubRepository implements OrganizerTeamRepository {
  ({OrganizerTeamId clubId, UserId inviteeUserId, String role})? lastInvite;

  @override
  Future<OrganizerTeamInvitationId?> invite(
    OrganizerTeamId clubId,
    UserId inviteeUserId, {
    String role = 'admin',
  }) async {
    lastInvite = (clubId: clubId, inviteeUserId: inviteeUserId, role: role);
    return OrganizerTeamInvitationId('inv-1');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _candidate = FriendCandidate(
  userId: 'u-2',
  nickname: 'Birgitta',
  relationship: FriendRelationship.none,
);

Future<_FakeClubRepository> _pumpScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = _FakeClubRepository();
  // Pop target route below the screen so the success path's context.pop()
  // has somewhere to go.
  final router = GoRouter(
    initialLocation: '/add',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Placeholder(),
        routes: [
          // Nested so '/add' stacks on '/', giving context.pop() a target.
          GoRoute(
            path: 'add',
            builder: (_, _) =>
                const OrganizerTeamAddMemberScreen(clubId: OrganizerTeamId('club-1')),
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        organizerTeamRepositoryProvider.overrideWithValue(repo),
        friendSearchProvider.overrideWith(
          (ref, query) async =>
              query.length < 2 ? const <FriendCandidate>[] : [_candidate],
        ),
      ],
      child: MaterialApp.router(
        theme: KubbTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('role picker renders with all three role segments',
      (tester) async {
    await _pumpScreen(tester);

    expect(find.text('Rolle'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Schiedsrichter'), findsOneWidget);
  });

  testWidgets('role picker defaults to admin', (tester) async {
    await _pumpScreen(tester);

    final picker = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(picker.selected, <String>{'admin'});
  });

  testWidgets(
      'selecting Schiedsrichter and inviting passes role=referee '
      'to the repository', (tester) async {
    final repo = await _pumpScreen(tester);

    await tester.tap(find.text('Schiedsrichter'));
    await tester.pumpAndSettle();
    final picker = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(picker.selected, <String>{'referee'});

    // Search for the candidate (>= 2 chars, 250 ms debounce), then invite.
    await tester.enterText(find.byType(TextField), 'bi');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Birgitta'), findsOneWidget);

    await tester.tap(find.text('Einladen'));
    await tester.pumpAndSettle();

    expect(repo.lastInvite, isNotNull);
    expect(repo.lastInvite!.clubId, const OrganizerTeamId('club-1'));
    expect(repo.lastInvite!.inviteeUserId, const UserId('u-2'));
    expect(repo.lastInvite!.role, 'referee');
  });
}
