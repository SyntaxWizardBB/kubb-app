import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/app/bootstrap.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/application/cloud_profile_provider.dart';
import 'package:kubb_app/features/auth/data/cloud_profile_repository.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';

class _StubAuthController extends AuthController {
  _StubAuthController(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;
}

void main() {
  testWidgets('App boots and renders the home greeting', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWith((ref) async => null),
          // M2: an onboarded profile so the onboarding redirect gate stays off.
          cloudProfileProvider.overrideWith((ref) async =>
              const CloudProfile(userId: 'test-user', nickname: 'Testuser')),
          authControllerProvider.overrideWith(
            () => _StubAuthController(
              const AuthSession.keypair(userId: 'test-id', displayName: 'Test'),
            ),
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
