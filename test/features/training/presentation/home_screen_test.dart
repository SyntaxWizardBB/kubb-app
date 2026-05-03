import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';
import 'package:kubb_app/features/training/presentation/home_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Player? profile,
    List<RecentSessionView> recent = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentProfileProvider.overrideWith((ref) async* {
            yield profile;
          }),
          recentSessionsProvider.overrideWithValue(recent),
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

  Player profileNamed(String name) => Player(
        id: 'p1',
        name: name,
        deviceId: 'd1',
        createdAt: DateTime.utc(2026, 5, 2),
      );

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
      recent: const [
        RecentSessionView(
          modeTag: 'Sniper',
          hitRatePercent: 64,
          subtitle: '8.0 m · 36 Würfe · gestern',
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('ZULETZT'), findsOneWidget);
    expect(find.text('SNIPER'), findsOneWidget);
    expect(find.text('64 %'), findsOneWidget);
  });

  testWidgets('FAB opens training sheet', (tester) async {
    await pump(tester, profile: profileNamed('Lukas'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Training'));
    await tester.pumpAndSettle();

    expect(find.text('Welcher Modus?'), findsOneWidget);
    expect(find.text('Sniper-Training'), findsOneWidget);
  });

  testWidgets('falls back to greeting without name when no profile',
      (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('Hallo.'), findsOneWidget);
  });
}
