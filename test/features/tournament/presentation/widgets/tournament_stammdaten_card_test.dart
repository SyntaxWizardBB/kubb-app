import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_stammdaten_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

TournamentDetailHeader _header({
  int teamSize = 1,
  int maxTeamSize = 1,
  String? clubId,
  TournamentScoring scoring = TournamentScoring.ekc,
  Map<String, Object?> cfg = const <String, Object?>{},
  Map<String, Object?> setup = const <String, Object?>{},
  TournamentStatus status = TournamentStatus.draft,
}) {
  return TournamentDetailHeader(
    tournamentId: 't-1',
    displayName: 'Sommer-Cup',
    createdByUserId: 'u-creator',
    clubId: clubId,
    teamSize: teamSize,
    maxTeamSize: maxTeamSize,
    minParticipants: 2,
    maxParticipants: 8,
    format: TournamentFormat.roundRobin,
    scoring: scoring,
    matchFormatConfig: cfg,
    tiebreakerOrder: const ['pts'],
    byePoints: null,
    forfeitPoints: null,
    status: status,
    publishedAt: null,
    startedAt: null,
    completedAt: null,
    setup: setup,
  );
}

Future<void> _pump(WidgetTester tester, TournamentDetailHeader header) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: TournamentStammdatenCard(header: header),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A maximal setup map covering B3.3 (KO/phase) + B3.4 (P6 metadata).
Map<String, Object?> _fullSetup() => <String, Object?>{
      // P6 metadata (B3.4)
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
      'consolation_bracket': <String, Object?>{
        'enabled': true,
        'name': 'Sieger der gebrochenen Herzen',
        'source': 'early_ko_losers',
        'source_rounds': <int>[1, 2],
        'direct_count': 4,
        'main_bracket_size': 16,
      },
      'rules_pdf_url': 'https://storage.example/tournament-pdfs/rules/x.pdf',
      'site_map_pdf_url': 'https://storage.example/tournament-pdfs/maps/y.pdf',
      // KO / phase config (B3.3)
      'bracket_type': 'double_elimination',
      'ko_tiebreak_method': 'mighty_finisher_shootout',
      'ko_matchup': 'seed_high_vs_low',
      'mighty_finisher_quali': <String, Object?>{
        'enabled': true,
        'slots': 4,
        'pool': 'group_runners_up',
        'method': 'mighty_finisher_shootout',
        'tiebreak': 'eight_meter_sudden_death',
      },
      'ko_config': <String, Object?>{
        'qualifier_count': 8,
        'with_third_place_playoff': true,
        'seeding_mode': 'manual',
      },
      'pool_phase_config': <String, Object?>{
        'group_count': 4,
        'qualifiers_per_group': 2,
        'strategy': 'snake',
      },
    };

/// A maximal core match-format config (B3.1/B3.2).
Map<String, Object?> _fullCfg() => <String, Object?>{
      'sets_to_win': 2,
      'max_sets': 3,
      'round_time_seconds': 1800,
      'basekubbs_per_side': 5,
      'tiebreak_enabled': true,
      'tiebreak_after_seconds': 600,
      'break_between_matches_seconds': 300,
      'final_no_tiebreak': true,
    };

void main() {
  testWidgets('renders all configured core fields (B3.1/B3.2)',
      (tester) async {
    await _pump(
      tester,
      _header(
        teamSize: 2,
        maxTeamSize: 4,
        scoring: TournamentScoring.classic,
        cfg: _fullCfg(),
      ),
    );

    // Core card heading + every configured value.
    expect(find.text('STAMMDATEN'), findsOneWidget);
    expect(find.text('Format'), findsOneWidget);
    expect(find.text('2–4 Spieler'), findsOneWidget); // team-size range
    expect(find.text('Wertung'), findsOneWidget);
    expect(find.text('Classic'), findsOneWidget); // scoring in core
    expect(find.text('2'), findsOneWidget); // sets_to_win
    expect(find.text('3'), findsOneWidget); // max_sets
    expect(find.text('30 min'), findsOneWidget); // round time (1800s)
    expect(find.text('5'), findsOneWidget); // basekubbs_per_side
    expect(find.text('Tiebreak nach 10 min'), findsOneWidget); // tiebreak
    expect(find.text('Pause zwischen Matches'), findsOneWidget); // break
    expect(find.text('5 min'), findsOneWidget); // break value (300s)
  });

  testWidgets('renders fixed team-size as a single value', (tester) async {
    // Defaults are teamSize:1 / maxTeamSize:1 → a fixed size.
    await _pump(tester, _header());
    expect(find.text('1 Spieler'), findsOneWidget);
    expect(find.textContaining('–'), findsNothing);
  });

  testWidgets('renders all configured KO/phase fields (B3.3)', (tester) async {
    await _pump(tester, _header(cfg: _fullCfg(), setup: _fullSetup()));

    expect(find.text('KO-PHASE'), findsOneWidget);
    expect(find.text('KO-Modell'), findsOneWidget);
    expect(find.text('Double-Elimination'), findsOneWidget);
    expect(find.text('KO-Tiebreak'), findsOneWidget);
    expect(find.text('Mighty Finisher'), findsWidgets); // label + tiebreak val
    expect(find.text('4 Plätze'), findsOneWidget); // mighty finisher slots
    expect(find.text('8 Qualifikanten'), findsOneWidget); // ko_config
    expect(find.text('Gruppen-Aufteilung'), findsOneWidget);
    expect(
        find.text('4 Gruppen, 2 qualifizieren'), findsOneWidget); // pool config

    // Newly surfaced KO fields (H2 — no silent omission).
    expect(find.text('Finale ohne Tiebreak'), findsOneWidget);
    expect(find.text('KO-Paarung'), findsOneWidget);
    expect(find.text('1 gegen n (Setzliste)'), findsOneWidget);
    expect(find.text('Spiel um Platz 3'), findsOneWidget);
    expect(find.text('Seeding'), findsOneWidget);
    expect(find.text('Manuell'), findsOneWidget);
    expect(find.text('Gruppen-Verteilung'), findsOneWidget);
    expect(find.text('Schlange (Snake)'), findsOneWidget);
    // Mighty-Finisher detail rows.
    expect(find.text('Mighty-Finisher Pool'), findsOneWidget);
    expect(find.text('Gruppenzweite'), findsOneWidget);
    expect(find.text('Mighty-Finisher Methode'), findsOneWidget);
    expect(find.text('Mighty-Finisher Tiebreak'), findsOneWidget);
    // Consolation detail rows (beyond the name).
    expect(find.text('Trostturnier-Quelle'), findsOneWidget);
    expect(find.text('Verlierer früher KO-Runden'), findsOneWidget);
    expect(find.text('Trostturnier Quell-Runden'), findsOneWidget);
    expect(find.text('1, 2'), findsOneWidget);
    expect(find.text('Direkt-Starter Trostturnier'), findsOneWidget);
    expect(find.text('Hauptfeld-Grösse'), findsOneWidget);
  });

  testWidgets('renders all configured P6 metadata (B3.4)', (tester) async {
    await _pump(tester, _header(clubId: 'club-1', setup: _fullSetup()));

    // Veranstaltung
    expect(find.text('VERANSTALTUNG'), findsOneWidget);
    expect(find.text('Bern'), findsOneWidget);
    expect(find.text('Wankdorfstrasse 1, 3014 Bern'), findsOneWidget);
    // Termine
    expect(find.text('TERMINE'), findsOneWidget);
    // Gebühr & Zahlung
    expect(find.text('GEBÜHR & ZAHLUNG'), findsOneWidget);
    expect(find.text('CHF 10.00'), findsOneWidget);
    expect(find.text('twint, cash'), findsOneWidget);
    // Kontakt
    expect(find.text('KONTAKT'), findsOneWidget);
    expect(find.text('Anna Meier'), findsOneWidget);
    expect(find.text('+41 79 123 45 67'), findsOneWidget);
    // Infos für Teilnehmer
    expect(find.text('INFOS FÜR TEILNEHMER'), findsOneWidget);
    expect(find.text('Foodtruck vor Ort'), findsOneWidget);
    expect(find.text('Bei Regen Verschiebung'), findsOneWidget);
    // Regel-Varianten
    expect(find.text('REGEL-VARIANTEN'), findsOneWidget);
    expect(find.text('2-4-6'), findsOneWidget); // opening rule
    // Veranstalter & Liga
    expect(find.text('A, B'), findsOneWidget); // league categories
    expect(find.text('Sieger der gebrochenen Herzen'), findsOneWidget);
    expect(find.text('club-1'), findsOneWidget);
    // Dokumente
    expect(find.text('DOKUMENTE'), findsOneWidget);
    expect(find.text('Regelwerk (PDF)'), findsOneWidget);
    expect(find.text('Geländeplan (PDF)'), findsOneWidget);
  });

  testWidgets('omits unset/NULL fields and empty sections entirely',
      (tester) async {
    // Minimal tournament: only the mandatory core fields, no P6, no KO.
    await _pump(
      tester,
      _header(cfg: const <String, Object?>{'sets_to_win': 2}),
    );

    // Core card still renders (Format / Team-Grösse / Wertung always).
    expect(find.text('STAMMDATEN'), findsOneWidget);

    // No optional core rows.
    expect(find.text('Basiskubbs/Seite'), findsNothing);
    expect(find.text('Tiebreak-Satz'), findsNothing);
    expect(find.text('Pause zwischen Matches'), findsNothing);
    expect(find.text('Max Sätze'), findsNothing);

    // No KO/phase section.
    expect(find.text('KO-PHASE'), findsNothing);
    expect(find.text('KO-Modell'), findsNothing);
    expect(find.text('Gruppen-Aufteilung'), findsNothing);

    // No P6 meta cards.
    expect(find.text('VERANSTALTUNG'), findsNothing);
    expect(find.text('TERMINE'), findsNothing);
    expect(find.text('GEBÜHR & ZAHLUNG'), findsNothing);
    expect(find.text('KONTAKT'), findsNothing);
    expect(find.text('INFOS FÜR TEILNEHMER'), findsNothing);
    expect(find.text('REGEL-VARIANTEN'), findsNothing);
    expect(find.text('DOKUMENTE'), findsNothing);
  });

  testWidgets('renders for an upcoming (non-live) tournament without error',
      (tester) async {
    // AC8: reusable for the upcoming-tournaments detail (same route/card).
    await _pump(
      tester,
      _header(
        status: TournamentStatus.registrationOpen,
        setup: <String, Object?>{'location': 'Bern'},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('STAMMDATEN'), findsOneWidget);
    expect(find.text('Bern'), findsOneWidget);
  });
}
