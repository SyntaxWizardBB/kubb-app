import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_detail_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _id = TournamentId('t-1');
const _creator = 'u-creator';

TournamentDetail _detail({
  TournamentStatus status = TournamentStatus.draft,
  List<TournamentParticipant> participants = const [],
  String? clubId,
}) {
  return TournamentDetail(
    tournament: TournamentDetailHeader(
      tournamentId: 't-1',
      displayName: 'Sommer-Cup',
      createdByUserId: _creator,
      clubId: clubId,
      teamSize: 1,
      maxTeamSize: 1,
      minParticipants: 2,
      maxParticipants: 8,
      format: TournamentFormat.roundRobin,
      scoring: TournamentScoring.ekc,
      matchFormatConfig: const <String, Object?>{
        'sets_to_win': 2,
        'max_sets': 3,
      },
      tiebreakerOrder: const ['pts', 'sets'],
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

Future<void> _pump(
  WidgetTester tester,
  TournamentDetail detail, {
  String? callerUserId,
  Bracket? bracket,
  bool canManage = false,
  String? manageableClubId,
  String? unmanageableClubId,
}) async {
  final router = GoRouter(
    initialLocation: '/tournament/t-1',
    routes: [
      GoRoute(
        path: '/tournament/:id',
        builder: (_, _) =>
            const TournamentDetailScreen(tournamentId: _id),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentDetailProvider(_id).overrideWith((_) async => detail),
        currentUserIdProvider.overrideWithValue(callerUserId),
        canManageTournamentClubProvider(null).overrideWithValue(canManage),
        if (manageableClubId != null)
          canManageTournamentClubProvider(manageableClubId)
              .overrideWithValue(true),
        if (unmanageableClubId != null)
          canManageTournamentClubProvider(unmanageableClubId)
              .overrideWithValue(false),
        tournamentBracketProvider(_id).overrideWith(
          (_) async => bracket ?? (throw ArgumentError('no ko matches')),
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
}

void main() {
  testWidgets('draft as creator shows publish action', (tester) async {
    await _pump(tester, _detail(), callerUserId: _creator);
    expect(find.text('Sommer-Cup'), findsWidgets);
    expect(find.text('Entwurf'), findsOneWidget);
    expect(find.text('Veröffentlichen'), findsOneWidget);
    expect(find.text('Anmelden'), findsNothing);
  });

  testWidgets('registration-open as outsider shows register action',
      (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.registrationOpen),
      callerUserId: 'u-other',
    );
    expect(find.text('Anmeldung offen'), findsOneWidget);
    expect(find.text('Anmelden'), findsOneWidget);
    expect(find.text('Veröffentlichen'), findsNothing);
  });

  testWidgets('aborted status surfaces the abort headline', (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.aborted),
      callerUserId: 'u-other',
    );
    expect(find.text('Turnier abgebrochen.'), findsOneWidget);
  });

  testWidgets('no bracket: hides bracket action while phase is group',
      (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.live),
      callerUserId: 'u-other',
    );
    expect(find.text('Bracket anzeigen'), findsNothing);
  });

  testWidgets('any KO match present: surfaces bracket action', (tester) async {
    final bracket =
        Bracket.singleElimination(const <String>['p1', 'p2', 'p3', 'p4']);
    await _pump(
      tester,
      _detail(status: TournamentStatus.live),
      callerUserId: 'u-other',
      bracket: bracket,
    );
    expect(find.text('Bracket anzeigen'), findsOneWidget);
  });

  testWidgets('P7: creator sees Bearbeiten while pre-start (published)',
      (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.published),
      callerUserId: _creator,
    );
    expect(find.text('Bearbeiten'), findsOneWidget);
  });

  testWidgets('P7: outsider never sees Bearbeiten', (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.published),
      callerUserId: 'u-other',
    );
    expect(find.text('Bearbeiten'), findsNothing);
  });

  testWidgets('P7: Bearbeiten hidden once the tournament is live',
      (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.live),
      callerUserId: _creator,
    );
    expect(find.text('Bearbeiten'), findsNothing);
  });

  testWidgets('P7: lifecycle hint shows for creator in draft', (tester) async {
    await _pump(tester, _detail(), callerUserId: _creator);
    expect(
      find.textContaining('die Anmeldung ist danach sofort offen'),
      findsOneWidget,
    );
  });

  testWidgets('P7: lifecycle hint shows for creator in published',
      (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.published),
      callerUserId: _creator,
    );
    expect(
      find.textContaining('Die Anmeldung ist offen'),
      findsOneWidget,
    );
  });

  testWidgets('P7: outsider does not see the lifecycle hint', (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.published),
      callerUserId: 'u-other',
    );
    expect(
      find.textContaining('Die Anmeldung ist offen'),
      findsNothing,
    );
  });

  testWidgets(
      'organizer (non-creator) sees the lifecycle actions: publish in draft',
      (tester) async {
    await _pump(
      tester,
      _detail(),
      callerUserId: 'u-organizer',
      canManage: true,
    );
    // Despite not being the creator, the organizer role surfaces the
    // publish action, the edit entry-point and the lifecycle hint.
    expect(find.text('Veröffentlichen'), findsOneWidget);
    expect(find.text('Bearbeiten'), findsOneWidget);
    expect(
      find.textContaining('die Anmeldung ist danach sofort offen'),
      findsOneWidget,
    );
  });

  testWidgets('organizer (non-creator) sees start in registration_closed',
      (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.registrationClosed),
      callerUserId: 'u-organizer',
      canManage: true,
    );
    expect(find.text('Turnier starten'), findsOneWidget);
  });

  testWidgets(
      'organizer (non-creator) sees finalize while live, not register',
      (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.live),
      callerUserId: 'u-organizer',
      canManage: true,
    );
    expect(find.text('Turnier abschliessen'), findsOneWidget);
    expect(find.text('Anmelden'), findsNothing);
  });

  testWidgets(
      'per-tournament club: non-creator owner/admin/organizer of THE '
      "tournament's club sees the lifecycle actions", (tester) async {
    // The tournament is linked to club c-1; the caller is not the creator
    // but manages that very club, so the per-tournament gate resolves true
    // and the lifecycle/edit actions surface.
    await _pump(
      tester,
      _detail(clubId: 'c-1'),
      callerUserId: 'u-club-admin',
      manageableClubId: 'c-1',
    );
    expect(find.text('Veröffentlichen'), findsOneWidget);
    expect(find.text('Bearbeiten'), findsOneWidget);
  });

  testWidgets(
      'per-tournament club: random non-creator WITHOUT the club role does '
      'not see the lifecycle actions', (tester) async {
    // Same club-linked tournament, but the caller neither created it nor
    // holds an owner/admin/organizer role in club c-1 (canManage stays
    // false for the c-1 family key), so no lifecycle/edit actions render.
    await _pump(
      tester,
      _detail(clubId: 'c-1'),
      callerUserId: 'u-stranger',
      unmanageableClubId: 'c-1',
    );
    expect(find.text('Veröffentlichen'), findsNothing);
    expect(find.text('Bearbeiten'), findsNothing);
  });

  // --- New open-registration model (Stage B) -------------------------------

  TournamentParticipant participant({
    required String id,
    required TournamentParticipantStatus status,
    String? userId,
    String label = 'Anna',
    DateTime? registeredAt,
  }) =>
      TournamentParticipant(
        participantId: id,
        userId: userId,
        nickname: label,
        displayName: label,
        registrationStatus: status,
        seed: null,
        registeredAt: registeredAt ?? DateTime(2026, 6),
        respondedAt: null,
      );

  testWidgets(
      'open-reg model: organizer sees Start (no "Anmeldung öffnen") once '
      'registration is open', (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.registrationOpen),
      callerUserId: 'u-organizer',
      canManage: true,
    );
    expect(find.text('Turnier starten'), findsOneWidget);
    expect(find.text('Anmeldung öffnen'), findsNothing);
  });

  testWidgets('open-reg model: confirmed registrant sees "Angemeldet"',
      (tester) async {
    await _pump(
      tester,
      _detail(
        status: TournamentStatus.registrationOpen,
        participants: [
          participant(
            id: 'p-1',
            userId: 'u-other',
            status: TournamentParticipantStatus.approved,
          ),
        ],
      ),
      callerUserId: 'u-other',
    );
    // No pending/awaiting-confirmation framing; the standing badge plus the
    // withdraw action are shown, the register action is gone.
    expect(find.text('Angemeldet'), findsWidgets);
    expect(find.text('Abmelden'), findsOneWidget);
    expect(find.text('Anmelden'), findsNothing);
  });

  testWidgets('open-reg model: waitlisted registrant sees "Auf Warteliste"',
      (tester) async {
    await _pump(
      tester,
      _detail(
        status: TournamentStatus.registrationOpen,
        participants: [
          participant(
            id: 'p-1',
            userId: 'u-other',
            status: TournamentParticipantStatus.waitlist,
          ),
        ],
      ),
      callerUserId: 'u-other',
    );
    expect(find.text('Auf Warteliste'), findsWidgets);
    expect(find.text('Abmelden'), findsOneWidget);
    expect(find.text('Anmelden'), findsNothing);
  });

  testWidgets(
      'open-reg model: non-registrant still sees the register action',
      (tester) async {
    await _pump(
      tester,
      _detail(
        status: TournamentStatus.registrationOpen,
        participants: [
          participant(
            id: 'p-1',
            userId: 'u-someone-else',
            status: TournamentParticipantStatus.approved,
          ),
        ],
      ),
      callerUserId: 'u-fresh',
    );
    expect(find.text('Anmelden'), findsOneWidget);
    expect(find.text('Abmelden'), findsNothing);
  });
}
