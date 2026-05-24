import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/data/auth_telemetry.dart';
import 'package:kubb_app/features/auth/data/dao/cached_auth_session_dao.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';

import '../../../_helpers/sqlite_open.dart';
import '../../../fixtures/auth/fake_secure_token_store.dart';
import '../../../fixtures/auth/fake_supabase_auth_adapter.dart';

void main() {
  setUpAll(registerLinuxSqliteOverride);

  late AppDatabase db;
  late CachedAuthSessionDao dao;
  late FakeSupabaseAuthAdapter adapter;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.cachedAuthSessionDao;
    adapter = FakeSupabaseAuthAdapter();
    container = ProviderContainer(
      overrides: [
        supabaseAuthAdapterProvider.overrideWithValue(adapter),
        cachedAuthSessionDaoProvider.overrideWithValue(dao),
        secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
        authTelemetryProvider.overrideWithValue(AuthTelemetry()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await adapter.dispose();
    await db.close();
  });

  test('boot with no cached session and signed-out adapter emits SignedOut',
      () async {
    final session = await container.read(authControllerProvider.future);
    expect(session, const AuthSession.signedOut());
  });

  test('boot with cached keypair session restores it without server call',
      () async {
    final now = DateTime.now().toUtc();
    await dao.upsert(
      userId: 'u1',
      kind: 'keypair',
      displayName: 'Lukas',
      avatarColor: '#FF8800',
      expiresAt: now.add(const Duration(hours: 1)),
      refreshAfter: now.add(const Duration(minutes: 50)),
    );

    final session = await container.read(authControllerProvider.future);
    expect(session, isA<KeypairSession>());
    expect(session.userId, 'u1');
    expect(session.displayName, 'Lukas');
  });

  test('boot with cached oauth_google session restores it', () async {
    final now = DateTime.now().toUtc();
    await dao.upsert(
      userId: 'u1',
      kind: 'oauth_google',
      displayName: 'Lukas',
      expiresAt: now.add(const Duration(hours: 1)),
      refreshAfter: now.add(const Duration(minutes: 50)),
    );

    final session = await container.read(authControllerProvider.future);
    expect(session, isA<OAuthSession>());
    final oauth = session as OAuthSession;
    expect(oauth.provider, AuthProvider.google);
  });

  test('adapter signInAnonymously transitions controller state to anonymous',
      () async {
    await container.read(authControllerProvider.future);

    await adapter.signInAnonymously();
    // Drain microtasks so the listener fires.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final session = container.read(authControllerProvider).value!;
    expect(session, isA<AnonymousSession>());
  });

  test('adapter oauth sign-in persists into the dao', () async {
    await container.read(authControllerProvider.future);

    await adapter.signInWithOAuth(AuthOAuthProvider.google);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final cached = await dao.current();
    expect(cached, isNotNull);
    expect(cached!.kind, 'oauth_google');
  });

  test('signOut clears the dao and emits SignedOut', () async {
    final now = DateTime.now().toUtc();
    await dao.upsert(
      userId: 'u1',
      kind: 'keypair',
      displayName: 'Lukas',
      expiresAt: now.add(const Duration(hours: 1)),
      refreshAfter: now.add(const Duration(minutes: 50)),
    );
    await container.read(authControllerProvider.future);

    await container.read(authControllerProvider.notifier).signOut();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(await dao.current(), isNull);
    expect(
      container.read(authControllerProvider).value,
      const AuthSession.signedOut(),
    );
  });

  test('a sign-in event in flight when signOut runs does not resurrect state',
      () async {
    // Reproduces the race that the generation counter guards against:
    // the adapter has emitted an anonymous-sign-in event but the
    // listener has not yet finished its async _persistSession await
    // when the user calls signOut. Without the generation guard the
    // pending listener would re-write SignedOut with a stale anonymous
    // session.
    await container.read(authControllerProvider.future);

    // Fire the event but do NOT drain microtasks — the listener has
    // queued its async work but signOut runs before that work
    // completes its dao persistence.
    await adapter.signInAnonymously();
    await container.read(authControllerProvider.notifier).signOut();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      container.read(authControllerProvider).value,
      const AuthSession.signedOut(),
      reason: 'in-flight sign-in event must not overwrite SignedOut',
    );
    expect(
      await dao.current(),
      isNull,
      reason: 'in-flight sign-in must not persist after signOut',
    );
  });
}
