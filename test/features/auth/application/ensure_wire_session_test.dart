import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/data/auth_telemetry.dart';
import 'package:kubb_app/features/auth/data/dao/cached_auth_session_dao.dart';

import '../../../_helpers/sqlite_open.dart';
import '../../../fixtures/auth/fake_secure_token_store.dart';
import '../../../fixtures/auth/fake_supabase_auth_adapter.dart';

/// Acceptance coverage for R1-F-02 (Mängel #9, `authentication required`
/// on tournament create). Drives [ensureWireSession] through every
/// branch: keypair re-sign, OAuth refresh, anonymous no-op, no-cache
/// no-op, and the failure paths that must not throw out of bootstrap.
void main() {
  setUpAll(registerLinuxSqliteOverride);

  late AppDatabase db;
  late CachedAuthSessionDao dao;
  late FakeSupabaseAuthAdapter adapter;
  late FakeSecureTokenStore secureStore;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.cachedAuthSessionDao;
    adapter = FakeSupabaseAuthAdapter();
    secureStore = FakeSecureTokenStore();
    container = ProviderContainer(
      overrides: [
        supabaseAuthAdapterProvider.overrideWithValue(adapter),
        cachedAuthSessionDaoProvider.overrideWithValue(dao),
        secureTokenStoreProvider.overrideWithValue(secureStore),
        authTelemetryProvider.overrideWithValue(AuthTelemetry()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await adapter.dispose();
    await db.close();
  });

  Future<void> seedCache({required String kind}) async {
    final now = DateTime.now().toUtc();
    await dao.upsert(
      userId: 'u1',
      kind: kind,
      displayName: 'Lukas',
      expiresAt: now.add(const Duration(hours: 1)),
      refreshAfter: now.add(const Duration(minutes: 50)),
    );
  }

  Future<void> seedPrivateKey() async {
    final keypair = container.read(keypairStorageProvider);
    final pair = await keypair.generate();
    await keypair.save(pair.privateKey);
  }

  test('returns alreadyLive when adapter has a wire token', () async {
    adapter.wireAccessTokenOverride = 'live-token';
    await seedCache(kind: 'keypair');

    final result = await container.read(ensureWireSessionProvider)();

    expect(result, WireSessionOutcome.alreadyLive);
  });

  test('returns noCachedSession when drift cache is empty', () async {
    adapter.wireAccessTokenOverride = null;

    final result = await container.read(ensureWireSessionProvider)();

    expect(result, WireSessionOutcome.noCachedSession);
  });

  test(
    'keypair cache without wire token triggers signInWithChallenge '
    'and reports keypairResigned',
    () async {
      // Drift cache holds a richer keypair session...
      await seedCache(kind: 'keypair');
      // ...but the underlying gotrue session is empty.
      adapter.wireAccessTokenOverride = null;
      // Private key is present in secure storage (signed-in once before).
      await seedPrivateKey();

      final result = await container.read(ensureWireSessionProvider)();

      expect(result, WireSessionOutcome.keypairResigned);
      // verifyKeypairSignature in the fake hydrates a fresh state with
      // kind = keypair. The wire-token override is independent of that
      // emission, so the assertion that counts is: the re-sign path ran.
      // (Live wire-token hydration is the responsibility of the real
      // adapter's recoverSession + onAuthStateChange round-trip.)
    },
  );

  test(
    'keypair cache without private key in secure storage is unrecoverable',
    () async {
      await seedCache(kind: 'keypair');
      adapter.wireAccessTokenOverride = null;
      // No private key seeded — cache says keypair, storage disagrees.

      final result = await container.read(ensureWireSessionProvider)();

      expect(result, WireSessionOutcome.unrecoverable);
    },
  );

  test(
    'oauth cache without wire token triggers refreshSession '
    'and reports oauthRefreshed',
    () async {
      await seedCache(kind: 'oauth_google');
      adapter
        ..wireAccessTokenOverride = null
        ..refreshTokenResult = 'refreshed-wire-token';

      final result = await container.read(ensureWireSessionProvider)();

      expect(result, WireSessionOutcome.oauthRefreshed);
      expect(adapter.refreshSessionCount, 1);
      expect(adapter.wireAccessTokenOverride, 'refreshed-wire-token');
    },
  );

  test('oauth refresh failure is swallowed and surfaces as failed', () async {
    await seedCache(kind: 'oauth_apple');
    adapter
      ..wireAccessTokenOverride = null
      ..throwOnNextCall = StateError('refresh denied');

    final result = await container.read(ensureWireSessionProvider)();

    expect(result, WireSessionOutcome.failed);
    // refresh attempted before the throw counter check increments the
    // counter, so we don't assert on it; the contract is "no rethrow".
  });

  test('anonymous cache is unrecoverable (no re-mint without losing id)',
      () async {
    await seedCache(kind: 'anonymous');
    adapter.wireAccessTokenOverride = null;

    final result = await container.read(ensureWireSessionProvider)();

    expect(result, WireSessionOutcome.unrecoverable);
  });
}
