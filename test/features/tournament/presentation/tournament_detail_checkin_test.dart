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

/// Minimal spying [TournamentRemote] for the D4 check-in UI tests. Records the
/// participant ids passed to [checkinParticipant] / [undoCheckin] so the
/// widget tests can assert the toggle wired the RPC. Every other port method
/// — including the realtime `watch*` streams the detail screen subscribes to —
/// degrades to a benign default (empty stream / no-op) so the screen builds
/// without a live Supabase client.
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
  group('D4-2 visibility gate (canManage + status window)', () {
    testWidgets('live + canManage: confirmed row shows the Einchecken toggle',
        (tester) async {
      await _pump(
        tester,
        _detail(
          status: TournamentStatus.live,
          participants: [_participant(id: 'p1')],
        ),
        callerUserId: 'u-other',
        canManage: true,
      );
      expect(find.text('Einchecken'), findsOneWidget);
    });

    testWidgets('registrationOpen + creator: toggle visible', (tester) async {
      await _pump(
        tester,
        _detail(
          status: TournamentStatus.registrationOpen,
          participants: [_participant(id: 'p1')],
        ),
        // Creator is always a manager (isCreator branch of canManage).
        callerUserId: _creator,
      );
      expect(find.text('Einchecken'), findsOneWidget);
    });

    testWidgets('draft: no toggle even for the creator', (tester) async {
      await _pump(
        tester,
        _detail(
          status: TournamentStatus.draft,
          participants: [_participant(id: 'p1')],
        ),
        callerUserId: _creator,
      );
      expect(find.text('Einchecken'), findsNothing);
      expect(find.text('Anwesend'), findsNothing);
    });

    testWidgets('finalized: no toggle (status outside window)', (tester) async {
      await _pump(
        tester,
        _detail(
          status: TournamentStatus.finalized,
          participants: [_participant(id: 'p1')],
        ),
        callerUserId: _creator,
        canManage: true,
      );
      expect(find.text('Einchecken'), findsNothing);
    });

    testWidgets('live but !canManage: no toggle', (tester) async {
      await _pump(
        tester,
        _detail(
          status: TournamentStatus.live,
          participants: [_participant(id: 'p1')],
        ),
        callerUserId: 'u-other',
      );
      expect(find.text('Einchecken'), findsNothing);
      expect(find.text('Anwesend'), findsNothing);
    });
  });

  testWidgets('D4-1: tapping Einchecken calls checkin with the participant id',
      (tester) async {
    final remote = await _pump(
      tester,
      _detail(
        status: TournamentStatus.live,
        participants: [_participant(id: 'p1')],
      ),
      callerUserId: 'u-other',
      canManage: true,
    );
    await tester.tap(find.text('Einchecken'));
    await tester.pumpAndSettle();
    expect(remote.checkins, ['p1']);
    expect(remote.undos, isEmpty);
  });

  testWidgets('D4-1/D4-3: a checked-in row shows Anwesend + timestamp label',
      (tester) async {
    await _pump(
      tester,
      _detail(
        status: TournamentStatus.live,
        participants: [
          _participant(
            id: 'p1',
            checkedInAt: DateTime.utc(2026, 6, 8, 12, 32),
          ),
        ],
      ),
      callerUserId: 'u-other',
      canManage: true,
    );
    expect(find.text('Anwesend'), findsOneWidget);
    expect(find.text('Einchecken'), findsNothing);
    // The localized "Eingecheckt <time>" label is present (D4-3).
    expect(
      find.textContaining('Eingecheckt'),
      findsOneWidget,
    );
  });

  testWidgets('D4-1: tapping Anwesend reverts via undoCheckin', (tester) async {
    final remote = await _pump(
      tester,
      _detail(
        status: TournamentStatus.live,
        participants: [
          _participant(
            id: 'p1',
            checkedInAt: DateTime.utc(2026, 6, 8, 12, 32),
          ),
        ],
      ),
      callerUserId: 'u-other',
      canManage: true,
    );
    await tester.tap(find.text('Anwesend'));
    await tester.pumpAndSettle();
    expect(remote.undos, ['p1']);
    expect(remote.checkins, isEmpty);
  });

  testWidgets('D4-5: header counter reports checked-in / total confirmed',
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
      callerUserId: 'u-other',
      canManage: true,
    );
    expect(find.text('1/3 eingecheckt'), findsOneWidget);
  });

  testWidgets('D4-12: waitlisted rows never get a check-in toggle',
      (tester) async {
    await _pump(
      tester,
      _detail(
        status: TournamentStatus.live,
        participants: [
          _participant(
            id: 'w1',
            status: TournamentParticipantStatus.waitlist,
          ),
        ],
      ),
      callerUserId: 'u-other',
      canManage: true,
    );
    expect(find.text('Einchecken'), findsNothing);
    expect(find.text('Auf Warteliste'), findsOneWidget);
  });
}
