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

// W4-T25: the on-site check-in that used to live inline on the detail screen
// now lives in the organizer cockpit (OrganizerDashboardDetailScreen). These
// tests assert the migrated check-in section wires the same RPCs.

const _id = TournamentId('t-1');
const _creator = 'u-creator';

class _SpyRemote implements TournamentRemote {
  final List<String> checkins = <String>[];
  final List<String> undos = <String>[];

  @override
  Future<void> checkinParticipant(TournamentParticipantId participantId) async {
    checkins.add(participantId.value);
  }

  @override
  Future<void> undoCheckin(TournamentParticipantId participantId) async {
    undos.add(participantId.value);
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
  DateTime? checkedInAt,
  String? displayName,
}) {
  return TournamentParticipant(
    participantId: id,
    userId: 'user-$id',
    nickname: null,
    displayName: displayName ?? 'Spieler $id',
    registrationStatus: status,
    seed: null,
    registeredAt: DateTime.utc(2026),
    respondedAt: null,
    checkedInAt: checkedInAt,
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

Future<void> _seek(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

void main() {
  group('check-in window gate (cockpit)', () {
    testWidgets('live: confirmed row shows the Einchecken toggle',
        (tester) async {
      await _pump(
        tester,
        _detail(
          status: TournamentStatus.live,
          participants: [_participant(id: 'p1')],
        ),
      );
      await _seek(tester, find.text('Einchecken'));
      expect(find.text('Einchecken'), findsOneWidget);
    });

    testWidgets('finalized: no check-in section (status outside window)',
        (tester) async {
      await _pump(
        tester,
        _detail(
          status: TournamentStatus.finalized,
          participants: [_participant(id: 'p1')],
        ),
      );
      expect(find.text('Einchecken'), findsNothing);
    });
  });

  testWidgets('tapping Einchecken calls checkin with the participant id',
      (tester) async {
    final remote = await _pump(
      tester,
      _detail(
        status: TournamentStatus.live,
        participants: [_participant(id: 'p1')],
      ),
    );
    await _seek(tester, find.text('Einchecken'));
    await tester.tap(find.text('Einchecken'));
    await tester.pumpAndSettle();
    expect(remote.checkins, ['p1']);
    expect(remote.undos, isEmpty);
  });

  testWidgets('a checked-in row shows Anwesend; tapping reverts via undoCheckin',
      (tester) async {
    final remote = await _pump(
      tester,
      _detail(
        status: TournamentStatus.live,
        participants: [
          _participant(id: 'p1', checkedInAt: DateTime.utc(2026, 6, 8, 12, 32)),
        ],
      ),
    );
    await _seek(tester, find.text('Anwesend'));
    expect(find.text('Anwesend'), findsOneWidget);
    expect(find.text('Einchecken'), findsNothing);
    await tester.tap(find.text('Anwesend'));
    await tester.pumpAndSettle();
    expect(remote.undos, ['p1']);
    expect(remote.checkins, isEmpty);
  });

  testWidgets('header counter reports checked-in / total confirmed',
      (tester) async {
    await _pump(
      tester,
      _detail(
        status: TournamentStatus.live,
        participants: [
          _participant(id: 'p1', checkedInAt: DateTime.utc(2026, 6, 8, 12)),
          _participant(id: 'p2'),
          _participant(id: 'p3'),
        ],
      ),
    );
    await _seek(tester, find.text('1/3 eingecheckt'));
    expect(find.text('1/3 eingecheckt'), findsOneWidget);
  });
}
