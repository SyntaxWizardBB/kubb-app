import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/app/bootstrap.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';

void main() {
  Player buildPlayer() => Player(
        id: 'p-router',
        name: 'Lukas',
        deviceId: 'd-router',
        createdAt: DateTime.utc(2026),
      );

  Future<void> pumpApp(
    WidgetTester tester, {
    required Player? bootstrap,
    required Stream<Player?> profileStream,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileBootstrapProvider.overrideWith((ref) async => bootstrap),
          appBootstrapProvider.overrideWith((ref) async {
            await ref.read(profileBootstrapProvider.future);
            return null;
          }),
          currentProfileProvider.overrideWith((ref) => profileStream),
          recentSessionsProvider.overrideWith(
            (ref) => Stream.value(const <RecentSessionView>[]),
          ),
          crashRecoveryProvider.overrideWith((ref) async => null),
        ],
        child: const KubbApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('A1: bootstrap=null + stream=null routes to onboarding',
      (tester) async {
    await pumpApp(
      tester,
      bootstrap: null,
      profileStream: Stream<Player?>.value(null),
    );

    expect(tester.takeException(), isNull);
    // onboardingHint "z.B. Lukas" is unique to the onboarding screen.
    expect(find.text('z.B. Lukas'), findsOneWidget);
    expect(find.text('Wie heisst du?'), findsOneWidget);
  });

  testWidgets(
      'A2-fallback: bootstrap=player + never-emitting stream uses initial '
      'snapshot and lands on home', (tester) async {
    final player = buildPlayer();
    final controller = StreamController<Player?>();
    addTearDown(controller.close);

    await pumpApp(
      tester,
      bootstrap: player,
      profileStream: controller.stream,
    );

    expect(tester.takeException(), isNull);
    // homeAppTitle is unique to the home scaffold; confirms the router used
    // the bootstrap snapshot instead of redirecting to onboarding.
    expect(find.text("Brosi's Kubb"), findsWidgets);
    // Onboarding hint must be absent — proves we are not on the onboarding
    // screen.
    expect(find.text('z.B. Lukas'), findsNothing);
  });
}
