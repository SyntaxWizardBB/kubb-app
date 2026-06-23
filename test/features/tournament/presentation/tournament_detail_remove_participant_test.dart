import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_detail_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _id = TournamentId('t-1');
const _creator = 'u-creator';

/// Records the participant ids passed to the two organizer-facing removal
/// paths so the test can prove the "Entfernen" button now routes to
/// [removeParticipant] (the setup-gated soft removal + waitlist promotion)
/// and no longer to the legacy [rejectRegistration].
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
  String? callerUserId,
  bool canManage = false,
}) async {
  final remote = _SpyRemote();
  final router = GoRouter(
    initialLocation: '/tournament/t-1',
    routes: [
      GoRoute(
        path: '/tournament/:id',
        builder: (_, _) => const TournamentDetailScreen(tournamentId: _id),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(remote),
        tournamentDetailProvider(_id).overrideWith((_) async => detail),
        currentUserIdProvider.overrideWithValue(callerUserId),
        canManageTournamentClubProvider(null).overrideWithValue(canManage),
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

void main() {
  testWidgets('confirm dialog routes Entfernen to removeParticipant',
      (tester) async {
    final remote = await _pump(
      tester,
      _detail(
        status: TournamentStatus.registrationOpen,
        participants: [_participant(id: 'p1')],
      ),
      callerUserId: 'u-other',
      canManage: true,
    );

    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();

    // The confirm dialog is up; the action button (also "Entfernen") sits
    // inside the AlertDialog. Tap it to commit.
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
      callerUserId: 'u-other',
      canManage: true,
    );

    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(TextButton, 'Abbrechen'),
    );
    await tester.pumpAndSettle();

    expect(remote.removed, isEmpty);
    expect(remote.rejected, isEmpty);
  });

  testWidgets('no remove button without manage rights', (tester) async {
    await _pump(
      tester,
      _detail(
        status: TournamentStatus.registrationOpen,
        participants: [_participant(id: 'p1')],
      ),
      callerUserId: 'u-other',
    );
    expect(find.text('Entfernen'), findsNothing);
  });

  testWidgets('waitlist row gets the remove button once canManage',
      (tester) async {
    final remote = await _pump(
      tester,
      _detail(
        status: TournamentStatus.registrationOpen,
        participants: [
          _participant(id: 'w1', status: TournamentParticipantStatus.waitlist),
        ],
      ),
      callerUserId: 'u-other',
      canManage: true,
    );

    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
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
