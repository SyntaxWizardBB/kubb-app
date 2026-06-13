import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/organizer_team/application/organizer_team_providers.dart';
import 'package:kubb_app/features/organizer_team/data/organizer_team_models.dart';
import 'package:kubb_app/features/tournament/application/server_clock_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/organizer_dashboard_screen.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/organizer_tournament_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

/// Records the control-RPC calls the card's quick action dispatches through
/// the actions facade, so the test can assert the right action fired.
class _SpyRemote extends FakeTournamentRemote {
  _SpyRemote() : super(initialUser: const UserId('u1'));

  final List<String> calls = <String>[];

  @override
  Future<void> pauseTournament(TournamentId id) async {
    calls.add('pause:${id.value}');
  }

  @override
  Future<void> startTournament(TournamentId id) async {
    calls.add('start:${id.value}');
    return;
  }

  @override
  Future<void> resumeTournament(TournamentId id) async {
    calls.add('resume:${id.value}');
  }
}

TournamentAdminCardRef _card({
  String id = 't-1',
  String name = 'Sommer-Cup',
  int? round = 3,
  RoundStatus? schedule = RoundStatus.running,
  int? remaining = 125,
  int open = 2,
  int disputed = 1,
  DateTime? pausedAt,
}) {
  return TournamentAdminCardRef(
    tournamentId: TournamentId(id),
    displayName: name,
    format: TournamentFormat.swiss,
    status: TournamentStatus.live,
    currentRound: round,
    scheduleStatus: schedule,
    remainingSeconds: remaining,
    openMatchCount: open,
    disputedMatchCount: disputed,
    pausedAt: pausedAt,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<TournamentAdminCardRef> cards,
  TournamentRemote? remote,
  List<OrganizerTeamWire> teams = const <OrganizerTeamWire>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        administrableTournamentsProvider.overrideWith((_) async => cards),
        serverClockOffsetProvider.overrideWith((_) async => Duration.zero),
        // P4-C: the teams section source — overridden so no Supabase runs.
        organizerTeamListProvider.overrideWith((_) async => teams),
        // Suppress the real 1s periodic so no timer leaks past the test.
        dashboardCountdownTickerProvider
            .overrideWithValue(const Stream<void>.empty()),
        if (remote != null) tournamentRemoteProvider.overrideWithValue(remote),
      ],
      child: MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OrganizerDashboardScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('renders a card per administrable tournament with badges',
      (tester) async {
    await _pump(tester, cards: [_card(), _card(id: 't-2', name: 'Herbst-Cup')]);

    expect(find.byType(OrganizerTournamentCard), findsNWidgets(2));
    expect(find.text('Sommer-Cup'), findsOneWidget);
    expect(find.text('Herbst-Cup'), findsOneWidget);
    // Phase/round + schedule status.
    expect(find.text('Runde 3'), findsWidgets);
    expect(find.text('Läuft'), findsWidgets);
    // Remaining-time readout (mm:ss, server-corrected, baseline 125s).
    expect(find.textContaining('02:05'), findsWidgets);
    // Open + disputed badges.
    expect(find.text('2 offen'), findsWidgets);
    expect(find.text('1 strittig'), findsWidgets);
  });

  testWidgets('running card primary action dispatches pause', (tester) async {
    final spy = _SpyRemote();
    await _pump(tester, cards: [_card()], remote: spy);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(spy.calls, contains('pause:t-1'));
  });

  testWidgets('paused card shows Fortsetzen and dispatches resume',
      (tester) async {
    final spy = _SpyRemote();
    await _pump(
      tester,
      cards: [_card(pausedAt: DateTime.utc(2026))],
      remote: spy,
    );

    expect(find.text('Pausiert'), findsOneWidget);
    await tester.tap(find.text('Fortsetzen'));
    await tester.pump();
    expect(spy.calls, contains('resume:t-1'));
  });

  testWidgets('no-schedule card offers Start', (tester) async {
    final spy = _SpyRemote();
    await _pump(
      tester,
      cards: [_card(round: null, schedule: null, remaining: null)],
      remote: spy,
    );

    expect(find.text('Noch keine aktive Runde'), findsOneWidget);
    await tester.tap(find.text('Starten'));
    await tester.pump();
    expect(spy.calls, contains('start:t-1'));
  });

  testWidgets('empty administrable list shows the empty/gate state',
      (tester) async {
    await _pump(tester, cards: const []);
    expect(find.byType(KubbEmptyState), findsOneWidget);
    expect(find.byType(OrganizerTournamentCard), findsNothing);
  });

  // P4-C (ADR-0032 §4): "Meine Veranstalterteams" section fed from
  // organizerTeamListProvider, trailing the tournament cards.
  testWidgets('renders the organizer teams section with team names',
      (tester) async {
    await _pump(
      tester,
      cards: [_card()],
      teams: [
        OrganizerTeamWire(
          id: 'c-1',
          displayName: 'Kubb Bären Bern',
          createdAt: DateTime.utc(2026),
        ),
      ],
    );

    expect(find.text('MEINE VERANSTALTERTEAMS'), findsOneWidget);
    expect(find.text('Kubb Bären Bern'), findsOneWidget);
    // The existing dashboard content stays intact next to the section.
    expect(find.byType(OrganizerTournamentCard), findsOneWidget);
  });

  testWidgets('hides the teams section when the caller has no teams',
      (tester) async {
    await _pump(tester, cards: [_card()]);

    expect(find.text('MEINE VERANSTALTERTEAMS'), findsNothing);
  });
}
