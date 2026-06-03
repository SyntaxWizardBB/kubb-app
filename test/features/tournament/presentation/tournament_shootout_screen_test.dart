import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/tournament_shootout_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_shootout_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Records report/confirm calls so the widget test can assert the action
/// reaches the repository. Pending list is returned from the override below.
class _RecordingRemote implements TournamentRemote {
  final List<({String shootoutId, List<TournamentParticipantId> order})>
      reportCalls = [];
  final List<({String shootoutId, List<TournamentParticipantId> order})>
      confirmCalls = [];

  @override
  Future<List<PendingShootout>> listPendingShootouts(TournamentId t) async =>
      const <PendingShootout>[];

  @override
  Future<void> reportShootoutWinners({
    required String shootoutId,
    required List<TournamentParticipantId> orderedWinners,
  }) async {
    reportCalls.add((shootoutId: shootoutId, order: orderedWinners));
  }

  @override
  Future<void> confirmShootout({
    required String shootoutId,
    required List<TournamentParticipantId> orderedWinners,
  }) async {
    confirmCalls.add((shootoutId: shootoutId, order: orderedWinners));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PendingShootout _so({
  List<String> ordered = const [],
  ShootoutStatus status = ShootoutStatus.pending,
}) {
  return PendingShootout(
    shootoutId: 'so-1',
    tournamentId: const TournamentId('t-1'),
    startRank: 1,
    tiedParticipants: const [
      ShootoutParticipantRef(
        participantId: TournamentParticipantId('p1'),
        displayName: 'Team Alpha',
      ),
      ShootoutParticipantRef(
        participantId: TournamentParticipantId('p2'),
        displayName: 'Team Beta',
      ),
    ],
    orderedWinners: [for (final p in ordered) TournamentParticipantId(p)],
    status: status,
  );
}

Future<_RecordingRemote> _pump(
  WidgetTester tester, {
  required List<PendingShootout> pending,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final remote = _RecordingRemote();
  final router = GoRouter(
    initialLocation: '/tournament/t-1/shootout/1',
    routes: [
      GoRoute(
        path: '/tournament/:id/shootout/:startRank',
        builder: (_, s) => TournamentShootoutScreen(
          tournamentId: s.pathParameters['id']!,
          startRank: int.parse(s.pathParameters['startRank']!),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(remote),
        pendingShootoutsProvider.overrideWith((ref, t) async => pending),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: KubbTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  return remote;
}

void main() {
  testWidgets('renders the tied participants and the report action',
      (tester) async {
    await _pump(tester, pending: [_so()]);

    expect(find.text('Team Alpha'), findsOneWidget);
    expect(find.text('Team Beta'), findsOneWidget);
    expect(find.text('Sieger melden'), findsOneWidget);
  });

  testWidgets('report action calls the repository with the chosen order',
      (tester) async {
    final remote = await _pump(tester, pending: [_so()]);

    await tester.tap(find.text('Sieger melden'));
    await tester.pump();

    expect(remote.reportCalls, hasLength(1));
    expect(remote.reportCalls.first.shootoutId, 'so-1');
    // Default order = stored tied order p1, p2.
    expect(
      remote.reportCalls.first.order.map((e) => e.value).toList(),
      ['p1', 'p2'],
    );
  });

  testWidgets('reported group shows the confirm action and calls confirm',
      (tester) async {
    final remote = await _pump(
      tester,
      pending: [_so(ordered: const ['p2', 'p1'], status: ShootoutStatus.reported)],
    );

    expect(find.text('Bestätigen'), findsOneWidget);
    await tester.tap(find.text('Bestätigen'));
    await tester.pump();

    expect(remote.confirmCalls, hasLength(1));
    // Confirmation sends the reported ordering exactly.
    expect(
      remote.confirmCalls.first.order.map((e) => e.value).toList(),
      ['p2', 'p1'],
    );
  });

  testWidgets('empty when no open shoot-out matches the start rank',
      (tester) async {
    await _pump(tester, pending: const <PendingShootout>[]);
    expect(find.text('Kein offener Shoot-Out'), findsOneWidget);
    expect(find.text('Sieger melden'), findsNothing);
  });

  testWidgets(
      'reported group locks reordering so confirm cannot send a divergent '
      'order (AC11)', (tester) async {
    final remote = await _pump(
      tester,
      pending: [
        _so(ordered: const ['p2', 'p1'], status: ShootoutStatus.reported),
      ],
    );

    // In the reported state all reorder controls are disabled: the confirming
    // side can only send the exact reported permutation. Asserting that every
    // chevron IconButton has a null onPressed proves the UI prevents a
    // divergent (ORDER_MISMATCH) submission rather than relying on the server.
    final chevrons = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .toList();
    expect(chevrons, isNotEmpty);
    for (final btn in chevrons) {
      expect(btn.onPressed, isNull);
    }

    // Confirm still sends exactly the reported ordering.
    await tester.tap(find.text('Bestätigen'));
    await tester.pump();
    expect(remote.confirmCalls, hasLength(1));
    expect(
      remote.confirmCalls.first.order.map((e) => e.value).toList(),
      ['p2', 'p1'],
    );
  });
}
