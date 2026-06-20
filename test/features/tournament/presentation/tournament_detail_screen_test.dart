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
  Map<String, Object?> setup = const <String, Object?>{},
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
      setup: setup,
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
  TournamentUrlOpener? urlOpener,
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
        if (urlOpener != null)
          tournamentUrlOpenerProvider.overrideWithValue(urlOpener),
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

  testWidgets('V2-B2: creator sees Bearbeiten while the tournament is live',
      (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.live),
      callerUserId: _creator,
    );
    expect(find.text('Bearbeiten'), findsOneWidget);
  });

  testWidgets('V2-B2: Bearbeiten hidden once the tournament is finalized',
      (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.finalized),
      callerUserId: _creator,
    );
    expect(find.text('Bearbeiten'), findsNothing);
  });

  testWidgets('aborted as creator shows Fortsetzen and Bearbeiten',
      (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.aborted),
      callerUserId: _creator,
    );
    expect(find.text('Turnier abgebrochen.'), findsOneWidget);
    expect(find.text('Fortsetzen'), findsOneWidget);
    expect(find.text('Bearbeiten'), findsOneWidget);
  });

  testWidgets('aborted as outsider shows neither Fortsetzen nor Bearbeiten',
      (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.aborted),
      callerUserId: 'u-other',
    );
    expect(find.text('Fortsetzen'), findsNothing);
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
    // A club-linked tournament now renders the "Veranstalter & Liga" meta
    // card (CF5/K28), so the lifecycle actions sit further down the lazily
    // built ListView — scroll them into view before asserting.
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Veröffentlichen'), 200,
        scrollable: list);
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

  testWidgets(
      'open-reg model: organizer can also register themselves — sees Anmelden '
      'alongside Start', (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.registrationOpen),
      callerUserId: 'u-organizer',
      canManage: true,
    );
    // The organizer keeps the lifecycle control AND gets a personal register
    // action (an organizer may play in their own tournament).
    expect(find.text('Turnier starten'), findsOneWidget);
    expect(find.text('Anmelden'), findsOneWidget);
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

  // ---- CF5/K28: meta-field rendering + PDF download -----------------------

  Map<String, Object?> fullSetup() => <String, Object?>{
        'location': 'Bern',
        'venue_address': 'Wankdorfstrasse 1, 3014 Bern',
        'event_starts_at': '2026-07-04T08:00:00.000Z',
        'registration_closes_at': '2026-06-30T22:00:00.000Z',
        'checkin_until': '2026-07-04T07:30:00.000Z',
        'entry_fee_cents': 1000,
        'currency': 'CHF',
        'payment_methods': <String>['twint', 'cash'],
        'contact_name': 'Anna Meier',
        'contact_phone': '+41 79 123 45 67',
        'info_food': 'Foodtruck vor Ort',
        'info_travel': 'Tram 9 bis Wankdorf',
        'info_accommodation': 'Hotel Bern',
        'weather_note': 'Bei Regen Verschiebung',
        'rule_variants': <String, Object?>{
          'diggy': true,
          'sureshot': false,
          'strafkubb_off_baseline': true,
          'opening_rule': '2-4-6',
        },
        'league_categories': <String>['a', 'b'],
        'ko_config': <String, Object?>{'qualifier_count': 8},
        'consolation_bracket': <String, Object?>{
          'enabled': true,
          'name': 'Sieger der gebrochenen Herzen',
        },
        'rules_pdf_url': 'https://storage.example/tournament-pdfs/rules/x.pdf',
        'site_map_pdf_url':
            'https://storage.example/tournament-pdfs/maps/y.pdf',
      };

  testWidgets('CF5/K28: detail screen renders the configured meta fields',
      (tester) async {
    await _pump(
      tester,
      _detail(clubId: 'club-1', setup: fullSetup()),
      callerUserId: 'u-other',
    );

    // The detail body is a long lazily-built ListView; scroll each
    // representative field into view before asserting. `scrollUntilVisible`
    // builds the off-screen card on the way.
    final list = find.byType(Scrollable).first;
    Future<void> seek(Finder f) async {
      await tester.scrollUntilVisible(f, 200, scrollable: list);
      expect(f, findsOneWidget);
    }

    // Card headings + representative values across the cards.
    await seek(find.text('VERANSTALTUNG'));
    await seek(find.text('Bern'));
    await seek(find.text('Wankdorfstrasse 1, 3014 Bern'));
    await seek(find.text('TERMINE'));
    await seek(find.text('GEBÜHR & ZAHLUNG'));
    await seek(find.text('CHF 10.00'));
    await seek(find.text('twint, cash'));
    await seek(find.text('KONTAKT'));
    await seek(find.text('Anna Meier'));
    await seek(find.text('INFOS FÜR TEILNEHMER'));
    await seek(find.text('Foodtruck vor Ort'));
    await seek(find.text('REGEL-VARIANTEN'));
    // Scoring shows 'EKC'.
    await seek(find.text('EKC'));
    // Consolation name surfaces in the organization card.
    await seek(find.text('Sieger der gebrochenen Herzen'));
  });

  testWidgets('CF5/K28: empty/minimal setup hides the optional cards',
      (tester) async {
    await _pump(tester, _detail(), callerUserId: 'u-other');
    // None of the optional meta-card headings appear.
    expect(find.text('VERANSTALTUNG'), findsNothing);
    expect(find.text('TERMINE'), findsNothing);
    expect(find.text('GEBÜHR & ZAHLUNG'), findsNothing);
    expect(find.text('KONTAKT'), findsNothing);
    expect(find.text('INFOS FÜR TEILNEHMER'), findsNothing);
    expect(find.text('DOKUMENTE'), findsNothing);
  });

  testWidgets('CF5/K28: PDF links appear and tapping opens the URL',
      (tester) async {
    final opened = <Uri>[];
    await _pump(
      tester,
      _detail(setup: fullSetup()),
      callerUserId: 'u-other',
      urlOpener: (url) async {
        opened.add(url);
        return true;
      },
    );

    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Regelwerk (PDF)'), 200,
        scrollable: list);
    expect(find.text('DOKUMENTE'), findsOneWidget);
    expect(find.text('Regelwerk (PDF)'), findsOneWidget);
    expect(find.text('Geländeplan (PDF)'), findsOneWidget);

    // H2: the Stammdaten card is now one tall ListView child, so make sure
    // the button is fully on-screen before tapping (the minimal scroll above
    // can leave it clipped at the viewport edge).
    await tester.ensureVisible(find.text('Regelwerk (PDF)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Regelwerk (PDF)'));
    await tester.pump();
    expect(opened, hasLength(1));
    expect(opened.single.toString(),
        'https://storage.example/tournament-pdfs/rules/x.pdf');
  });

  testWidgets('CF5/K28: no PDF link when the URLs are unset', (tester) async {
    await _pump(
      tester,
      _detail(setup: const <String, Object?>{'location': 'Bern'}),
      callerUserId: 'u-other',
    );
    expect(find.text('DOKUMENTE'), findsNothing);
    expect(find.text('Regelwerk (PDF)'), findsNothing);
    expect(find.text('Geländeplan (PDF)'), findsNothing);
  });

  // CF6 (K19): the mandatory seeding step surfaces only for manual seeding
  // when the tournament is live and the KO bracket hasn't been built yet.
  testWidgets('CF6: live manual-seeding tournament shows "Seeding festlegen"',
      (tester) async {
    await _pump(
      tester,
      _detail(
        status: TournamentStatus.live,
        setup: const <String, Object?>{
          'ko_config': <String, Object?>{
            'qualifier_count': 4,
            'seeding_mode': 'manual',
          },
        },
      ),
      callerUserId: _creator,
      canManage: true,
    );
    // Action buttons sit at the bottom of the scroll view (below the fold
    // at the default test window size), so include offstage candidates.
    expect(
      find.text('Seeding festlegen', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('CF6: live auto-seeding tournament shows no seeding CTA',
      (tester) async {
    await _pump(
      tester,
      _detail(
        status: TournamentStatus.live,
        setup: const <String, Object?>{
          'ko_config': <String, Object?>{
            'qualifier_count': 4,
            'seeding_mode': 'auto',
          },
        },
      ),
      callerUserId: _creator,
      canManage: true,
    );
    expect(find.text('Seeding festlegen', skipOffstage: false), findsNothing);
  });
}
