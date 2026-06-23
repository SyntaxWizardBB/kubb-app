import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/organizer_team/application/organizer_team_providers.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/tournament/application/my_active_match_provider.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';
import 'package:kubb_app/features/training/presentation/home_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    DisplayProfile? profile,
    List<RecentSessionView> recent = const [],
    bool organizerVisible = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          displayProfileProvider.overrideWithValue(profile),
          recentActivityProvider.overrideWith((ref) async => recent),
          crashRecoveryProvider.overrideWith((ref) async => null),
          // P4-C: organizer tile gate — overridden so no Supabase call runs.
          organizerTileVisibleProvider
              .overrideWith((ref) async => organizerVisible),
          // P5-C: ongoing-match tile source — overridden (null = hidden) so
          // no registration/match fetch runs in these layout tests.
          myActiveTournamentMatchProvider.overrideWith(
            (ref) => const AsyncValue<MyActiveTournamentMatch?>.data(null),
          ),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  DisplayProfile profileNamed(String name) =>
      DisplayProfile(userId: 'p1', displayName: name);

  testWidgets('renders greeting with profile name', (tester) async {
    await pump(tester, profile: profileNamed('Lukas'));
    await tester.pumpAndSettle();

    expect(find.text('Hallo, Lukas.'), findsOneWidget);
  });

  testWidgets('hides recent section when list is empty', (tester) async {
    await pump(tester, profile: profileNamed('Lukas'));
    await tester.pumpAndSettle();

    expect(find.text('ZULETZT'), findsNothing);
  });

  testWidgets('shows recent rows when list has items', (tester) async {
    await pump(
      tester,
      profile: profileNamed('Lukas'),
      recent: [
        RecentSessionView(
          modeTag: 'Sniper',
          hitRatePercent: 64,
          completedAt: DateTime.utc(2026, 5, 2),
          subtitle: '8.0 m · 36 Würfe · gestern',
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('ZULETZT'), findsOneWidget);
    expect(find.text('SNIPER'), findsOneWidget);
    expect(find.text('64 %'), findsOneWidget);
  });

  // P4-C (ADR-0032 §4): the former "Meine Vereine" tile is now the
  // organizer tile, gated by organizerTileVisibleProvider.
  testWidgets('shows the Veranstalter tile when the gate is true',
      (tester) async {
    await pump(tester, profile: profileNamed('Lukas'), organizerVisible: true);
    await tester.pumpAndSettle();

    expect(find.text('Veranstalter'), findsOneWidget);
    expect(find.text('Dashboard & Veranstalterteams'), findsOneWidget);
  });

  testWidgets('hides the Veranstalter tile when the gate is false',
      (tester) async {
    await pump(tester, profile: profileNamed('Lukas'));
    await tester.pumpAndSettle();

    expect(find.text('Veranstalter'), findsNothing);
    expect(find.text('Dashboard & Veranstalterteams'), findsNothing);
    // The remaining home tiles stay in place (fail-closed gate only
    // removes the organizer tile, never breaks the rest of the layout).
    expect(find.text('Meine Teams'), findsOneWidget);
    // Spec §4: the old "Match-Modus / In Vorbereitung" placeholder tile is
    // gone; with no active match the green pitch banner is hidden too.
    expect(find.text('Match-Modus'), findsNothing);
    expect(find.byKey(const ValueKey('pitch-call-banner')), findsNothing);
  });

  testWidgets('falls back to greeting without name when no profile',
      (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('Hallo.'), findsOneWidget);
  });

  testWidgets('renders home scaffold without throwing when profile is null',
      (tester) async {
    await pump(tester, organizerVisible: true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Veranstalter'), findsOneWidget);
  });
}
