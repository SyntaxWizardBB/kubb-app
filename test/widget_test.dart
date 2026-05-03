import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';

void main() {
  testWidgets('App boots and renders the placeholder home', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentProfileProvider.overrideWith(
            (ref) => Stream<Player?>.value(
              Player(
                id: 'test-id',
                name: 'Test',
                deviceId: 'test-device',
                createdAt: DateTime.utc(2026),
              ),
            ),
          ),
        ],
        child: const KubbApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
