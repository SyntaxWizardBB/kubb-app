import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/organizer_dashboard_detail_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

// W4-T25: participant moderation ("Entfernen") moved from the detail screen
// into the organizer cockpit. These tests assert the migrated moderation
// section routes to the server-gated `removeParticipant` (soft removal +
// waitlist promotion), never the legacy reject.

const _id = TournamentId('t-1');
const _creator = 'u-creator';

class _SpyRemote implements TournamentRemote {
  final List<String> removed = <String>[];
  final List<String> rejected = <String>[];

  @override
  Future<void> removeParticipant(
    TournamentParticipantId participantId, {
    String? reason,
  }) async {
    removed.add(participantId.value);
  }

  @override
  Future<void> rejectRegistration(TournamentParticipantId participantId) async {
    rejected.add(participantId.value);
  }

  @override
  Stream<TournamentParticipant> watchTournamentParticipants(
    TournamentId tournamentId,
  ) =>
      const Stream<TournamentParticipant>.empty();

  @override
  Stream<TournamentMatchRef> watchTournamentMatches(TournamentId tournamentId) =>
      const Stream<TournamentMatchRef>.empty();

  @override
  Stream<BracketAdvanceEvent> watchBracketAdvances(TournamentId tournamentId) =>
      const Stream<BracketAdvanceEvent>.empty();

  @override
  Future<DateTime> fetchServerNow() async => DateTime.now().toUtc();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

TournamentParticipant _participant({
  required String id,
  TournamentParticipantStatus status = TournamentParticipantStatus.approved,
}) {
  return TournamentParticipant(
    participantId: id,
    userId: 'user-$id',
    nickname: null,
    displayName: 'Spieler $id',
    registrationStatus: status,
    seed: null,
    registeredAt: DateTime.utc(2026),
    respondedAt: null,
  );
}

TournamentDetail _detail({
  required TournamentStatus status,
  List<TournamentParticipant> participants = const [],
}) {
  return TournamentDetail(
    tournament: TournamentDetailHeader(
      tournamentId: 't-1',
      displayName: 'Sommer-Cup',
      createdByUserId: _creator,
      clubId: null,
      teamSize: 1,
      maxTeamSize: 1,
      minParticipants: 2,
      maxParticipants: 8,
      format: TournamentFormat.roundRobin,
      scoring: TournamentScoring.ekc,
      matchFormatConfig: const <String, Object?>{},
      tiebreakerOrder: const ['pts'],
      byePoints: null,
      forfeitPoints: null,
      status: status,
      publishedAt: null,
      startedAt: null,
      completedAt: null,
    ),
    participants: participants,
    matches: const [],
    auditTail: const [],
  );
}

Future<_SpyRemote> _pump(
  WidgetTester tester,
  TournamentDetail detail, {
  bool canAdminister = true,
}) async {
  final remote = _SpyRemote();
  final router = GoRouter(
    initialLocation: '/tournament/t-1/dashboard',
    routes: [
      GoRoute(
        path: '/tournament/t-1/dashboard',
        builder: (_, _) =>
            const OrganizerDashboardDetailScreen(tournamentId: _id),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(remote),
        tournamentDetailProvider(_id).overrideWith((_) async => detail),
        canAdministerTournamentProvider((
          clubId: null,
          createdBy: _creator,
        )).overrideWithValue(canAdminister),
        tournamentMatchListProvider(_id).overrideWith((_) async => const []),
        tournamentRoundScheduleProvider(_id)
            .overrideWith((_) => Stream.value(const {})),
        tournamentBracketProvider(_id).overrideWith(
          (_) async => throw ArgumentError('no ko matches'),
        ),
      ],
      child: MaterialApp.router(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return remote;
}

Future<void> _tapRemove(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Entfernen'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.text('Entfernen'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Entfernen'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('confirm dialog routes Entfernen to removeParticipant',
      (tester) async {
    final remote = await _pump(
      tester,
      _detail(
        status: TournamentStatus.registrationOpen,
        participants: [_participant(id: 'p1')],
      ),
    );

    await _tapRemove(tester);
    final dialogAction = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Entfernen'),
    );
    expect(dialogAction, findsOneWidget);
    await tester.tap(dialogAction);
    await tester.pumpAndSettle();

    expect(remote.removed, ['p1']);
    expect(remote.rejected, isEmpty);
  });

  testWidgets('cancelling the dialog invokes neither removal path',
      (tester) async {
    final remote = await _pump(
      tester,
      _detail(
        status: TournamentStatus.registrationOpen,
        participants: [_participant(id: 'p1')],
      ),
    );

    await _tapRemove(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Abbrechen'));
    await tester.pumpAndSettle();

    expect(remote.removed, isEmpty);
    expect(remote.rejected, isEmpty);
  });

  testWidgets('no remove button without administer rights', (tester) async {
    await _pump(
      tester,
      _detail(
        status: TournamentStatus.registrationOpen,
        participants: [_participant(id: 'p1')],
      ),
      canAdminister: false,
    );
    // The gate replaces the whole body with the empty state.
    expect(find.text('Entfernen'), findsNothing);
  });

  testWidgets('waitlist row gets the remove button too', (tester) async {
    final remote = await _pump(
      tester,
      _detail(
        status: TournamentStatus.registrationOpen,
        participants: [
          _participant(id: 'w1', status: TournamentParticipantStatus.waitlist),
        ],
      ),
    );

    await _tapRemove(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Entfernen'),
      ),
    );
    await tester.pumpAndSettle();

    expect(remote.removed, ['w1']);
    expect(remote.rejected, isEmpty);
  });
}
