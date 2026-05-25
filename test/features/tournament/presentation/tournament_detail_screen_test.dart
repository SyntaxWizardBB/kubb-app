import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_models.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_detail_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _id = TournamentId('t-1');
const _creator = 'u-creator';

TournamentDetail _detail({
  TournamentStatus status = TournamentStatus.draft,
  List<TournamentParticipant> participants = const [],
}) {
  return TournamentDetail(
    tournament: TournamentDetailHeader(
      tournamentId: 't-1',
      displayName: 'Sommer-Cup',
      createdByUserId: _creator,
      teamSize: 1,
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
}
