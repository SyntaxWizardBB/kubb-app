import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/app/bootstrap.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';

void main() {
  testWidgets('App boots and renders the home greeting', (tester) async {
    final player = Player(
      id: 'test-id',
      name: 'Test',
      deviceId: 'test-device',
      createdAt: DateTime.utc(2026),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileBootstrapProvider.overrideWith((ref) async => player),
          appBootstrapProvider.overrideWith((ref) async {
            await ref.read(profileBootstrapProvider.future);
            return null;
          }),
          currentProfileProvider.overrideWith(
            (ref) => Stream<Player?>.value(player),
          ),
          displayProfileProvider.overrideWithValue(
            const DisplayProfile(userId: 'test-id', displayName: 'Test'),
          ),
          recentSessionsProvider.overrideWith(
            (ref) => Stream.value(const <RecentSessionView>[]),
          ),
          crashRecoveryProvider.overrideWith((ref) async => null),
        ],
        child: const KubbApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Hallo, Test.'), findsOneWidget);
  });
}
