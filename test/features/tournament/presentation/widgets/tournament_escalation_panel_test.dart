import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_escalation_panel.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _id = TournamentId('t-1');

/// Spying remote: records the forfeit declared by the No-Show shortcut so the
/// pre-fill (side + reason) can be asserted. Everything else throws if hit,
/// because the panel must not perform any other server call.
class _SpyRemote implements TournamentRemote {
  ({TournamentMatchId matchId, ForfeitAbsentSide side, String reason})? lastCall;

  @override
  Future<void> declareForfeit({
    required TournamentMatchId matchId,
    required ForfeitAbsentSide absentSide,
    required String reason,
  }) async {
    lastCall = (matchId: matchId, side: absentSide, reason: reason);
  }

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

TournamentMatchRef _match({
  required String id,
  required TournamentMatchStatus status,
  String? aId,
  String? bId,
  String aName = 'A',
  String bName = 'B',
  int round = 1,
  int number = 1,
}) {
  return TournamentMatchRef(
    matchId: TournamentMatchId(id),
    tournamentId: _id,
    roundNumber: round,
    matchNumberInRound: number,
    participantA: aId == null ? null : TournamentParticipantId(aId),
    participantB: bId == null ? null : TournamentParticipantId(bId),
    participantADisplayName: aName,
    participantBDisplayName: bName,
    status: status,
    consensusRound: 1,
  );
}

TournamentDetail _detail({
  TournamentStatus status = TournamentStatus.live,
  List<TournamentParticipant> participants = const [],
  List<TournamentMatchRef> matches = const [],
}) {
  return TournamentDetail(
    tournament: TournamentDetailHeader(
      tournamentId: 't-1',
      displayName: 'Sommer-Cup',
      createdByUserId: 'u-creator',
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
      forfeitPoints: 18,
      status: status,
      publishedAt: null,
      startedAt: null,
      completedAt: null,
    ),
    participants: participants,
    matches: matches,
    auditTail: const [],
  );
}

class _PushSpy {
  String? lastOverrideLocation;
}

Future<_SpyRemote> _pump(
  WidgetTester tester,
  TournamentDetail detail, {
  bool canManage = true,
  _PushSpy? pushSpy,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final remote = _SpyRemote();
  final router = GoRouter(
    initialLocation: '/panel',
    routes: [
      GoRoute(
        path: '/panel',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(
            child: TournamentEscalationPanel(
              detail: detail,
              tournamentId: _id,
              canManage: canManage,
            ),
          ),
        ),
      ),
      // Override target — the disputed-row CTA pushes here; we record the
      // location instead of rendering the real override screen.
      GoRoute(
        path: '/tournament/:tid/match/:mid/override',
        builder: (ctx, state) {
          pushSpy?.lastOverrideLocation = state.uri.toString();
          return const Scaffold(body: Text('OVERRIDE'));
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(remote),
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
  group('disputed list', () {
    testWidgets('positive: a disputed match surfaces under Strittig',
        (tester) async {
      await _pump(
        tester,
        _detail(matches: [
          _match(
            id: 'm-d',
            status: TournamentMatchStatus.disputed,
            aId: 'p1',
            bId: 'p2',
            aName: 'Anton',
            bName: 'Berta',
          ),
        ]),
      );
      expect(find.text('Strittig'), findsOneWidget);
      expect(find.text('Anton — Berta'), findsOneWidget);
    });

    testWidgets('negative: a finalized match is not listed as disputed',
        (tester) async {
      await _pump(
        tester,
        _detail(matches: [
          _match(
            id: 'm-f',
            status: TournamentMatchStatus.finalized,
            aId: 'p1',
            bId: 'p2',
          ),
        ]),
      );
      expect(find.text('Strittig'), findsNothing);
    });

    testWidgets('override entry: disputed CTA pushes the override route',
        (tester) async {
      final spy = _PushSpy();
      await _pump(
        tester,
        _detail(matches: [
          _match(
            id: 'm-d',
            status: TournamentMatchStatus.disputed,
            aId: 'p1',
            bId: 'p2',
          ),
        ]),
        pushSpy: spy,
      );
      await tester.tap(find.text('Korrigieren'));
      await tester.pumpAndSettle();
      expect(spy.lastOverrideLocation, '/tournament/t-1/match/m-d/override');
    });
  });

  group('overdue list', () {
    testWidgets('positive: an awaiting_results match surfaces under Überfällig',
        (tester) async {
      await _pump(
        tester,
        _detail(matches: [
          _match(
            id: 'm-o',
            status: TournamentMatchStatus.awaitingResults,
            aId: 'p1',
            bId: 'p2',
            aName: 'Carl',
            bName: 'Dora',
          ),
        ]),
      );
      expect(find.text('Überfällig'), findsOneWidget);
      expect(find.text('Carl — Dora'), findsOneWidget);
    });

    testWidgets('negative: a scheduled match is not overdue', (tester) async {
      await _pump(
        tester,
        _detail(matches: [
          _match(
            id: 'm-s',
            status: TournamentMatchStatus.scheduled,
            aId: 'p1',
            bId: 'p2',
          ),
        ]),
      );
      expect(find.text('Überfällig'), findsNothing);
    });
  });

  group('not-checked-in list', () {
    testWidgets('positive: a confirmed participant without check-in is listed',
        (tester) async {
      await _pump(
        tester,
        _detail(participants: [
          _participant(id: 'p1', displayName: 'Emil'),
        ]),
      );
      expect(find.text('Nicht eingecheckt'), findsOneWidget);
      expect(find.text('Emil'), findsOneWidget);
    });

    testWidgets('negative: a checked-in confirmed participant is not listed',
        (tester) async {
      await _pump(
        tester,
        _detail(participants: [
          _participant(
            id: 'p1',
            displayName: 'Emil',
            checkedInAt: DateTime.utc(2026, 6, 8, 10),
          ),
        ]),
      );
      expect(find.text('Nicht eingecheckt'), findsNothing);
      expect(find.text('Emil'), findsNothing);
    });

    testWidgets('negative: a waitlisted participant is not listed',
        (tester) async {
      await _pump(
        tester,
        _detail(participants: [
          _participant(
            id: 'p1',
            displayName: 'Wartend',
            status: TournamentParticipantStatus.waitlist,
          ),
        ]),
      );
      expect(find.text('Nicht eingecheckt'), findsNothing);
    });
  });

  group('No-Show → Forfait shortcut', () {
    TournamentDetail noShowDetail({
      TournamentStatus status = TournamentStatus.live,
      TournamentMatchStatus matchStatus = TournamentMatchStatus.scheduled,
    }) {
      return _detail(
        status: status,
        participants: [_participant(id: 'p1', displayName: 'Emil')],
        matches: [
          _match(
            id: 'm-1',
            status: matchStatus,
            aId: 'p1',
            bId: 'p2',
          ),
        ],
      );
    }

    testWidgets('visible: live tournament + forfeitable match shows the CTA',
        (tester) async {
      await _pump(tester, noShowDetail());
      expect(find.text('No-Show → Forfait'), findsOneWidget);
    });

    testWidgets('hidden: tournament not live hides the CTA', (tester) async {
      await _pump(
        tester,
        noShowDetail(status: TournamentStatus.registrationClosed),
      );
      // The participant still shows (registration closed is a confirmed pool),
      // but no forfeit CTA because the tournament is not live.
      expect(find.text('Nicht eingecheckt'), findsOneWidget);
      expect(find.text('No-Show → Forfait'), findsNothing);
    });

    testWidgets('hidden: non-forfeitable match status hides the CTA',
        (tester) async {
      await _pump(
        tester,
        noShowDetail(matchStatus: TournamentMatchStatus.finalized),
      );
      expect(find.text('Nicht eingecheckt'), findsOneWidget);
      expect(find.text('No-Show → Forfait'), findsNothing);
    });

    testWidgets('hidden: canManage false hides the CTA entirely',
        (tester) async {
      await _pump(tester, noShowDetail(), canManage: false);
      expect(find.text('No-Show → Forfait'), findsNothing);
    });

    testWidgets(
        'pre-fill: shortcut opens the forfeit sheet with absentSide A + reason',
        (tester) async {
      final remote = await _pump(tester, noShowDetail());
      await tester.tap(find.text('No-Show → Forfait'));
      await tester.pumpAndSettle();
      // Sheet is open and pre-filled. Submit (button is enabled because both
      // side and a >=10 char reason are seeded) and assert the wired values.
      await tester.tap(find.text('Forfeit speichern'));
      await tester.pumpAndSettle();
      expect(remote.lastCall, isNotNull);
      expect(remote.lastCall!.matchId, const TournamentMatchId('m-1'));
      // p1 sits on side A of the match → absentSide A.
      expect(remote.lastCall!.side, ForfeitAbsentSide.a);
      expect(remote.lastCall!.reason, 'No-Show - nicht eingecheckt');
    });

    testWidgets('pre-fill: absentSide follows the participant match side (B)',
        (tester) async {
      final detail = _detail(
        participants: [_participant(id: 'p2', displayName: 'Berta')],
        matches: [
          _match(
            id: 'm-2',
            status: TournamentMatchStatus.scheduled,
            aId: 'p1',
            bId: 'p2',
          ),
        ],
      );
      final remote = await _pump(tester, detail);
      await tester.tap(find.text('No-Show → Forfait'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forfeit speichern'));
      await tester.pumpAndSettle();
      expect(remote.lastCall!.side, ForfeitAbsentSide.b);
    });

    testWidgets('only one side per match is offered a forfeit shortcut',
        (tester) async {
      // Both sides are not checked in and sit in the same forfeitable match.
      final detail = _detail(
        participants: [
          _participant(id: 'p1', displayName: 'Emil'),
          _participant(id: 'p2', displayName: 'Berta'),
        ],
        matches: [
          _match(
            id: 'm-1',
            status: TournamentMatchStatus.scheduled,
            aId: 'p1',
            bId: 'p2',
          ),
        ],
      );
      await _pump(tester, detail);
      // Both participants are listed, but the forfeit CTA appears exactly
      // once (for the first side only).
      expect(find.text('Emil'), findsOneWidget);
      expect(find.text('Berta'), findsOneWidget);
      expect(find.text('No-Show → Forfait'), findsOneWidget);
    });
  });

  testWidgets('empty: no escalations renders the empty state', (tester) async {
    await _pump(
      tester,
      _detail(
        participants: [
          _participant(
            id: 'p1',
            checkedInAt: DateTime.utc(2026, 6, 8, 10),
          ),
        ],
        matches: [
          _match(
            id: 'm-f',
            status: TournamentMatchStatus.finalized,
            aId: 'p1',
            bId: 'p2',
          ),
        ],
      ),
    );
    expect(find.text('Alles im grünen Bereich'), findsOneWidget);
    expect(find.text('Strittig'), findsNothing);
    expect(find.text('Überfällig'), findsNothing);
    expect(find.text('Nicht eingecheckt'), findsNothing);
  });
}
