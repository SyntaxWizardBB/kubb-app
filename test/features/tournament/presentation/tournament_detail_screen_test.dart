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

/// Records pushed routes so the "→ Steuerung" button can be asserted to land on
/// the cockpit detail route.
class _RouteSpy {
  final List<String> pushed = <String>[];
}

class _PushObserver extends NavigatorObserver {
  _PushObserver(this.spy);
  final _RouteSpy spy;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) spy.pushed.add(name);
    super.didPush(route, previousRoute);
  }
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
  _RouteSpy? routeSpy,
}) async {
  final router = GoRouter(
    initialLocation: '/tournament/t-1',
    observers: routeSpy == null ? const [] : [_PushObserver(routeSpy)],
    routes: [
      GoRoute(
        path: '/tournament/:id',
        builder: (_, _) => const TournamentDetailScreen(tournamentId: _id),
      ),
      // Cockpit destination stub so the "→ Steuerung" push resolves.
      GoRoute(
        path: '/tournament/:id/dashboard',
        builder: (_, _) => const Scaffold(body: Text('COCKPIT')),
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

TournamentParticipant _participant({
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

void main() {
  // ── W4-T25: the detail screen is the SAME player view for everyone ──────
  // No organizer blocks inline. A manager only gets the "→ Steuerung" button.

  group('unified player view — no organizer blocks inline', () {
    for (final status in TournamentStatus.values) {
      testWidgets('manager sees no lifecycle/checkin/moderation block ($status)',
          (tester) async {
        await _pump(
          tester,
          _detail(
            status: status,
            participants: [
              _participant(
                id: 'p1',
                userId: 'u-someone',
                status: TournamentParticipantStatus.approved,
              ),
            ],
          ),
          callerUserId: 'u-organizer',
          canManage: true,
        );
        // Lifecycle actions are gone from the detail screen.
        expect(find.text('Veröffentlichen'), findsNothing);
        expect(find.text('Anmeldung schliessen'), findsNothing);
        expect(find.text('Turnier abschliessen'), findsNothing);
        expect(find.text('Turnier abbrechen'), findsNothing);
        expect(find.text('Bearbeiten'), findsNothing);
        expect(find.text('Seeding festlegen', skipOffstage: false),
            findsNothing);
        // Moderation + check-in are gone.
        expect(find.text('Entfernen'), findsNothing);
        expect(find.text('Einchecken'), findsNothing);
        expect(find.text('Anwesend'), findsNothing);
      });
    }

    testWidgets('manager sees the "→ Steuerung" dashboard button', (tester) async {
      await _pump(
        tester,
        _detail(status: TournamentStatus.registrationOpen),
        callerUserId: 'u-organizer',
        canManage: true,
      );
      expect(find.text('→ Turnier-Steuerung'), findsOneWidget);
    });

    testWidgets('non-manager never sees the dashboard button', (tester) async {
      await _pump(
        tester,
        _detail(status: TournamentStatus.registrationOpen),
        callerUserId: 'u-other',
      );
      expect(find.text('→ Turnier-Steuerung'), findsNothing);
    });

    testWidgets('dashboard button routes to the cockpit detail', (tester) async {
      final spy = _RouteSpy();
      await _pump(
        tester,
        _detail(status: TournamentStatus.live),
        callerUserId: 'u-organizer',
        canManage: true,
        routeSpy: spy,
      );
      await tester.tap(find.text('→ Turnier-Steuerung'));
      await tester.pumpAndSettle();
      // The navigator observer records the route PATTERN, not the concrete URL.
      expect(spy.pushed, contains('/tournament/:id/dashboard'));
    });

    testWidgets('no lifecycle hint anywhere on the detail screen',
        (tester) async {
      await _pump(tester, _detail(), callerUserId: _creator, canManage: true);
      expect(
        find.textContaining('die Anmeldung ist danach sofort offen'),
        findsNothing,
      );
    });
  });

  // ── Player-only actions stay on the detail screen ───────────────────────

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

  testWidgets('open-reg: confirmed registrant sees "Angemeldet" + withdraw',
      (tester) async {
    await _pump(
      tester,
      _detail(
        status: TournamentStatus.registrationOpen,
        participants: [
          _participant(
            id: 'p-1',
            userId: 'u-other',
            status: TournamentParticipantStatus.approved,
          ),
        ],
      ),
      callerUserId: 'u-other',
    );
    expect(find.text('Angemeldet'), findsWidgets);
    expect(find.text('Abmelden'), findsOneWidget);
    expect(find.text('Anmelden'), findsNothing);
  });

  testWidgets('open-reg: waitlisted registrant sees "Auf Warteliste"',
      (tester) async {
    await _pump(
      tester,
      _detail(
        status: TournamentStatus.registrationOpen,
        participants: [
          _participant(
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

  testWidgets('open-reg: non-registrant still sees the register action',
      (tester) async {
    await _pump(
      tester,
      _detail(
        status: TournamentStatus.registrationOpen,
        participants: [
          _participant(
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

  testWidgets('participant list renders read-only rows for everyone',
      (tester) async {
    await _pump(
      tester,
      _detail(
        status: TournamentStatus.live,
        participants: [
          _participant(
            id: 'p-1',
            userId: 'u-a',
            status: TournamentParticipantStatus.pending,
          ),
        ],
      ),
      callerUserId: 'u-other',
      canManage: true,
    );
    expect(find.text('Anna'), findsWidgets);
    // Read-only: no check-in/remove affordance even for a manager.
    expect(find.text('Einchecken'), findsNothing);
    expect(find.text('Entfernen'), findsNothing);
  });

  testWidgets('aborted status surfaces the abort headline for everyone',
      (tester) async {
    await _pump(
      tester,
      _detail(status: TournamentStatus.aborted),
      callerUserId: 'u-other',
    );
    expect(find.text('Turnier abgebrochen.'), findsOneWidget);
    // No resume/edit — those are cockpit-only now.
    expect(find.text('Fortsetzen'), findsNothing);
    expect(find.text('Bearbeiten'), findsNothing);
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

  testWidgets('any KO match present: surfaces bracket action for everyone',
      (tester) async {
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

  // ---- CF5/K28: meta-field rendering + PDF download (player view) ---------

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

    final list = find.byType(Scrollable).first;
    Future<void> seek(Finder f) async {
      await tester.scrollUntilVisible(f, 200, scrollable: list);
      expect(f, findsOneWidget);
    }

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
    await seek(find.text('EKC'));
    await seek(find.text('Sieger der gebrochenen Herzen'));
  });

  testWidgets('CF5/K28: empty/minimal setup hides the optional cards',
      (tester) async {
    await _pump(tester, _detail(), callerUserId: 'u-other');
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
}
