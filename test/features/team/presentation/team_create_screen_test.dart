// Widget regression for Mängel #3: the team-create button must
// re-enable and a snackbar must surface when the server fails the
// create_team RPC. Also asserts that a warning log entry is emitted
// via Logger('team.membership').
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_app/features/team/presentation/team_create_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:logging/logging.dart';

class _FailingTeamRepo implements TeamRepository {
  @override
  Future<TeamId> createTeam({
    required String displayName,
    required LeagueMembership leagueMembership,
    String? logoUrl,
    String? country,
  }) async {
    throw const TeamPermissionException('not_authenticated');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester tester, TeamRepository repo) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/teams/new',
    routes: [
      GoRoute(
        path: '/teams/new',
        builder: (_, _) => const TeamCreateScreen(),
      ),
      GoRoute(
        path: '/teams/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detail-${state.pathParameters['id']}')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        teamRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'server error keeps the submit button enabled and surfaces a snackbar '
      'while emitting a Logger warning', (tester) async {
    final originalLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(() async {
      await sub.cancel();
      Logger.root.level = originalLevel;
    });

    await _pump(tester, _FailingTeamRepo());

    // Type into the name field so the submit button enables.
    await tester.enterText(find.byType(TextField).first, 'Hammer-Crew');
    await tester.pump();

    final submitFinder = find.widgetWithText(FilledButton, 'Team anlegen');
    expect(submitFinder, findsOneWidget);
    expect(
      tester.widget<FilledButton>(submitFinder).onPressed,
      isNotNull,
      reason: 'submit must start enabled once the name field is filled',
    );

    await tester.tap(submitFinder);
    await tester.pump(); // start the async submit
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    // Snackbar surfaces the localized error message.
    expect(
      find.text('Team konnte nicht erstellt werden — bitte erneut versuchen.'),
      findsOneWidget,
    );

    // Button is re-enabled so the user can retry.
    expect(
      tester.widget<FilledButton>(submitFinder).onPressed,
      isNotNull,
      reason: 'button must re-enable after the failure',
    );

    // Logger spy caught the warning. Payload is PII-free: just the
    // RPC name, no UUIDs, no display name, no email.
    final warnings = records
        .where((r) => r.level == Level.WARNING && r.loggerName == 'team.membership')
        .toList();
    expect(warnings, isNotEmpty);
    final entry = warnings.single;
    expect(entry.message, contains('team action failed'));
    expect(entry.error, 'rpc=team_create');
    expect(entry.stackTrace, isNotNull);
  });
}
