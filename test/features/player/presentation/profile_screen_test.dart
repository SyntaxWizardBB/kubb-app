import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/player/presentation/profile_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de');
  });

  Future<void> pump(
    WidgetTester tester, {
    required AsyncValue<Player?> profile,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentProfileProvider.overrideWith((ref) async* {
            if (profile is AsyncData<Player?>) {
              yield profile.value;
            }
          }),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders player name when profile is loaded', (tester) async {
    final player = Player(
      id: 'p1',
      name: 'Lukas',
      deviceId: 'd1',
      createdAt: DateTime.utc(2026, 5, 2),
    );
    await pump(tester, profile: AsyncData(player));
    await tester.pumpAndSettle();

    expect(find.text('Lukas'), findsOneWidget);
    expect(find.text('Geräte-ID'), findsOneWidget);
    expect(find.text('Mitglied seit'), findsOneWidget);
    expect(find.text('d1'), findsOneWidget);
  });

  testWidgets('shows loading indicator while profile is loading',
      (tester) async {
    await pump(tester, profile: const AsyncLoading<Player?>());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows fallback when profile is null', (tester) async {
    await pump(tester, profile: const AsyncData<Player?>(null));
    await tester.pumpAndSettle();

    expect(find.text('Kein Profil'), findsOneWidget);
  });
}
