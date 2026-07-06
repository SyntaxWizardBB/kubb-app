import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/application/cloud_profile_provider.dart';
import 'package:kubb_app/features/auth/application/nickname_self_heal_provider.dart';
import 'package:kubb_app/features/auth/data/cloud_profile_repository.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';

import '../../../fixtures/auth/fake_supabase_auth_adapter.dart';

/// Emits a fixed [AuthSession] synchronously.
class _StubAuthController extends AuthController {
  _StubAuthController(this._session);
  final AuthSession _session;

  @override
  Future<AuthSession> build() async => _session;
}

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderContainer _container({
  required AuthSession session,
  required CloudProfile? profile,
  required FakeSupabaseAuthAdapter adapter,
}) {
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(() => _StubAuthController(session)),
      cloudProfileProvider.overrideWith((ref) async => profile),
      supabaseAuthAdapterProvider.overrideWithValue(adapter),
    ],
  );
  addTearDown(container.dispose);
  // Activate the lifetime side-effect provider (as `app.dart` does).
  container.read(nicknameSelfHealProvider);
  return container;
}

void main() {
  group('nicknameSelfHeal', () {
    test('OAuth session with empty display name is backfilled from the profile',
        () async {
      final adapter = FakeSupabaseAuthAdapter();
      await adapter.signInWithOAuth(AuthOAuthProvider.google);
      _container(
        session: const AuthSession.oauth(
          userId: 'u-oauth',
          displayName: '',
          provider: AuthProvider.google,
        ),
        profile: const CloudProfile(userId: 'u-oauth', nickname: 'Samuel'),
        adapter: adapter,
      );

      await _settle();

      expect(adapter.updateNicknameCount, 1);
      expect(adapter.lastUpdatedNickname, 'Samuel');
    });

    test('session that already has a display name is left untouched', () async {
      final adapter = FakeSupabaseAuthAdapter();
      await adapter.signInWithOAuth(AuthOAuthProvider.google);
      _container(
        session: const AuthSession.oauth(
          userId: 'u-oauth',
          displayName: 'Samuel',
          provider: AuthProvider.google,
        ),
        profile: const CloudProfile(userId: 'u-oauth', nickname: 'Samuel'),
        adapter: adapter,
      );

      await _settle();

      expect(adapter.updateNicknameCount, 0);
    });

    test('no cloud profile yet → no write (onboarding will seed it)', () async {
      final adapter = FakeSupabaseAuthAdapter();
      await adapter.signInWithOAuth(AuthOAuthProvider.google);
      _container(
        session: const AuthSession.oauth(
          userId: 'u-oauth',
          displayName: '',
          provider: AuthProvider.google,
        ),
        profile: null,
        adapter: adapter,
      );

      await _settle();

      expect(adapter.updateNicknameCount, 0);
    });

    test('anonymous session is ignored', () async {
      final adapter = FakeSupabaseAuthAdapter();
      await adapter.signInAnonymously();
      _container(
        session: const AuthSession.anonymous(userId: 'u-anon'),
        profile: const CloudProfile(userId: 'u-anon', nickname: 'whatever'),
        adapter: adapter,
      );

      await _settle();

      expect(adapter.updateNicknameCount, 0);
    });

    test('heals at most once even across repeated session emissions',
        () async {
      final adapter = FakeSupabaseAuthAdapter();
      await adapter.signInWithOAuth(AuthOAuthProvider.google);
      final container = _container(
        session: const AuthSession.oauth(
          userId: 'u-oauth',
          displayName: '',
          provider: AuthProvider.google,
        ),
        profile: const CloudProfile(userId: 'u-oauth', nickname: 'Samuel'),
        adapter: adapter,
      );

      await _settle();
      // Re-emit the same empty-name session; the guard must suppress a
      // second write.
      container.read(authControllerProvider.notifier).state = const AsyncData(
        AuthSession.oauth(
          userId: 'u-oauth',
          displayName: '',
          provider: AuthProvider.google,
        ),
      );
      await _settle();

      expect(adapter.updateNicknameCount, 1);
    });
  });
}
