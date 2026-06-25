import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/account_upgrade_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/data/auth_deep_link_service.dart';
import 'package:kubb_app/features/auth/data/auth_telemetry.dart';
import 'package:kubb_app/features/auth/data/crypto_service.dart';
import 'package:kubb_app/features/auth/data/dao/cached_auth_session_dao.dart';
import 'package:kubb_app/features/auth/data/keypair_storage.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';

import '../../_helpers/sqlite_open.dart';
import '../../fixtures/auth/fake_secure_token_store.dart';
import '../../fixtures/auth/fake_supabase_auth_adapter.dart';

const _keypairUserId = 'keypair-user';

/// Hands the ambient [Ref] to a test so it can build an
/// [AuthDeepLinkService] without the real `AppLinks()` singleton (which
/// would reach for platform channels). The service is constructed but
/// never `start()`ed — the test drives [AuthDeepLinkService.handle]
/// directly.
final _refProbeProvider = Provider<Ref>((ref) => ref);

void main() {
  setUpAll(registerLinuxSqliteOverride);

  late AppDatabase db;
  late CachedAuthSessionDao dao;
  late FakeSupabaseAuthAdapter adapter;
  late FakeSecureTokenStore secureStore;
  late KeypairStorage keypair;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.cachedAuthSessionDao;
    adapter = FakeSupabaseAuthAdapter();
    secureStore = FakeSecureTokenStore();
    keypair = KeypairStorage(crypto: CryptoService(), secureStore: secureStore);
    container = ProviderContainer(
      overrides: [
        supabaseAuthAdapterProvider.overrideWithValue(adapter),
        cachedAuthSessionDaoProvider.overrideWithValue(dao),
        secureTokenStoreProvider.overrideWithValue(secureStore),
        keypairStorageProvider.overrideWithValue(keypair),
        authTelemetryProvider.overrideWithValue(AuthTelemetry()),
      ],
    );
    adapter.reconcileUserId = _keypairUserId;
  });

  tearDown(() async {
    container.dispose();
    await adapter.dispose();
    await db.close();
  });

  test(
      'in-flight upgrade drops a forked OAuth emission so the cache keeps the '
      'keypair user_id (kill-mid-flow safe)', () async {
    final now = DateTime.now().toUtc();
    await dao.upsert(
      userId: _keypairUserId,
      kind: 'keypair',
      displayName: 'Lukas',
      expiresAt: now.add(const Duration(hours: 12)),
      refreshAfter: now.add(const Duration(hours: 11)),
    );
    await container.read(authControllerProvider.future);

    // Arm the clobber gate the way AccountUpgradeController does just
    // before awaitingCallback.
    container
        .read(upgradeInFlightProvider.notifier)
        .mark(const UpgradeInFlight(keypairUserId: _keypairUserId));

    // getSessionFromUrl installs the FORKED OAuth session (different
    // user_id). This is the emission that must be suppressed.
    await adapter.signInWithOAuth(AuthOAuthProvider.google);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final session = container.read(authControllerProvider).value;
    expect(
      session,
      isA<KeypairSession>(),
      reason: 'forked OAuth emission must not replace the keypair session',
    );
    expect(session!.userId, _keypairUserId);

    // The drift cache — the source of truth across a cold start — must
    // still hold the keypair user_id, so a kill mid-flow recovers it.
    final cached = await dao.current();
    expect(cached, isNotNull);
    expect(cached!.kind, 'keypair');
    expect(cached.userId, _keypairUserId);
  });

  test('once the flag clears, an OAuth emission is honoured again', () async {
    await container.read(authControllerProvider.future);
    container
        .read(upgradeInFlightProvider.notifier)
        .mark(const UpgradeInFlight(keypairUserId: _keypairUserId));
    container.read(upgradeInFlightProvider.notifier).clear();

    await adapter.signInWithOAuth(AuthOAuthProvider.google);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(container.read(authControllerProvider).value, isA<OAuthSession>());
  });

  test(
      'callback after the timeout cleared the flag does not install the forked '
      'session over an active keypair identity (FIX 1)', () async {
    // Shrink the timeout so it fires before the callback arrives.
    container.dispose();
    container = ProviderContainer(
      overrides: [
        supabaseAuthAdapterProvider.overrideWithValue(adapter),
        cachedAuthSessionDaoProvider.overrideWithValue(dao),
        secureTokenStoreProvider.overrideWithValue(secureStore),
        keypairStorageProvider.overrideWithValue(keypair),
        authTelemetryProvider.overrideWithValue(AuthTelemetry()),
        upgradeCallbackTimeoutProvider
            .overrideWithValue(const Duration(milliseconds: 20)),
      ],
    );

    final now = DateTime.now().toUtc();
    await dao.upsert(
      userId: _keypairUserId,
      kind: 'keypair',
      displayName: 'Lukas',
      expiresAt: now.add(const Duration(hours: 12)),
      refreshAfter: now.add(const Duration(hours: 11)),
    );
    await keypair.save(List<int>.filled(32, 7));
    await container.read(authControllerProvider.future);

    // Start the upgrade, then let the 3-min (here: 20ms) window elapse so
    // the timeout clears the in-flight flag and the controller lands in
    // failed(callback_timeout) — the exact edge FIX 1 closes.
    await container
        .read(accountUpgradeControllerProvider.notifier)
        .linkOAuth(AuthProvider.google);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(container.read(upgradeInFlightProvider), isNull,
        reason: 'timeout must have cleared the flag');
    expect(
      container.read(accountUpgradeControllerProvider),
      const AccountUpgradeState.failed(
        code: 'callback_timeout',
        provider: AuthProvider.google,
      ),
    );

    // The forked OAuth callback arrives LATE. Route it through the deep
    // link service exactly as the platform stream would.
    final service = AuthDeepLinkService(container.read(_refProbeProvider));
    await service.handle(Uri.parse('kubbapp://auth/callback?code=late'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // The cold getSessionFromUrl path must NOT have run — that is what
    // would have clobbered the keypair user_id.
    expect(adapter.completeSignInCount, 0,
        reason: 'late callback must not take the forked cold-start path');

    // Active session and the drift cache still hold the keypair user_id.
    final session = container.read(authControllerProvider).value;
    expect(session?.userId, _keypairUserId);
    final cached = await dao.current();
    expect(cached, isNotNull);
    expect(cached!.userId, _keypairUserId,
        reason: 'forked OAuth user_id must never reach the cache');
  });
}
