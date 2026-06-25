import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/account_upgrade_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/data/auth_telemetry.dart';
import 'package:kubb_app/features/auth/data/crypto_service.dart';
import 'package:kubb_app/features/auth/data/keypair_storage.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';
import 'package:logging/logging.dart';

import '../../_helpers/sqlite_open.dart';
import '../../fixtures/auth/fake_secure_token_store.dart';
import '../../fixtures/auth/fake_supabase_auth_adapter.dart';

const _keypairUserId = 'keypair-user';

/// Telemetry whose accountUpgrade throws, to simulate a post-reconcile
/// step blowing up after the server already committed the link. The
/// reconcile itself succeeds; only this trailing call fails.
class _ThrowingTelemetry extends AuthTelemetry {
  @override
  void accountUpgrade({required String userId, required String toKind}) {
    throw StateError('telemetry blew up after the link committed');
  }
}

void main() {
  setUpAll(registerLinuxSqliteOverride);

  late AppDatabase db;
  late FakeSupabaseAuthAdapter adapter;
  late FakeSecureTokenStore secureStore;
  late KeypairStorage keypair;
  late List<LogRecord> telemetryRecords;
  late ProviderContainer container;

  Future<void> seedKeypairSession() async {
    final now = DateTime.now().toUtc();
    await db.cachedAuthSessionDao.upsert(
      userId: _keypairUserId,
      kind: 'keypair',
      displayName: 'Lukas',
      expiresAt: now.add(const Duration(hours: 12)),
      refreshAfter: now.add(const Duration(hours: 11)),
    );
  }

  setUp(() async {
    db = await openTestDatabase();
    adapter = FakeSupabaseAuthAdapter();
    secureStore = FakeSecureTokenStore();
    keypair = KeypairStorage(crypto: CryptoService(), secureStore: secureStore);
    telemetryRecords = <LogRecord>[];
    final logger = Logger.detached('upgrade-test-${identityHashCode(db)}')
      ..level = Level.ALL
      ..onRecord.listen(telemetryRecords.add);

    container = ProviderContainer(
      overrides: [
        cachedAuthSessionDaoProvider.overrideWithValue(db.cachedAuthSessionDao),
        supabaseAuthAdapterProvider.overrideWithValue(adapter),
        keypairStorageProvider.overrideWithValue(keypair),
        secureTokenStoreProvider.overrideWithValue(secureStore),
        authTelemetryProvider.overrideWithValue(AuthTelemetry(logger: logger)),
      ],
    );
    adapter.reconcileUserId = _keypairUserId;
  });

  tearDown(() async {
    container.dispose();
    await adapter.dispose();
    await db.close();
  });

  test('no seed on device fails with keypair_seed_missing and starts no oauth',
      () async {
    await seedKeypairSession();
    await container.read(authControllerProvider.future);

    await container
        .read(accountUpgradeControllerProvider.notifier)
        .linkOAuth(AuthProvider.google);

    final state = container.read(accountUpgradeControllerProvider);
    expect(
      state,
      const AccountUpgradeState.failed(
        code: 'keypair_seed_missing',
        provider: AuthProvider.google,
      ),
    );
    expect(adapter.oauthCount, 0, reason: 'browser must not open without seed');
    expect(adapter.linkOAuthCount, 0);
  });

  test('after launching, state is awaitingCallback — never an early done',
      () async {
    await keypair.save(List<int>.filled(32, 7));
    await seedKeypairSession();
    await container.read(authControllerProvider.future);

    await container
        .read(accountUpgradeControllerProvider.notifier)
        .linkOAuth(AuthProvider.google);

    final state = container.read(accountUpgradeControllerProvider);
    expect(state, const AccountUpgradeState.awaitingCallback(AuthProvider.google));
    expect(adapter.linkOAuthCount, 1);
  });

  test('completeLink success emits OAuthSession with unchanged id and telemetry',
      () async {
    await keypair.save(List<int>.filled(32, 7));
    await seedKeypairSession();
    await container.read(authControllerProvider.future);

    final notifier =
        container.read(accountUpgradeControllerProvider.notifier);
    await notifier.linkOAuth(AuthProvider.google);
    await notifier.completeLink(Uri.parse('kubbapp://auth/callback?code=abc'));

    expect(
      container.read(accountUpgradeControllerProvider),
      const AccountUpgradeState.done(),
    );

    final session = container.read(authControllerProvider).value;
    expect(session, isA<OAuthSession>());
    final oauth = session! as OAuthSession;
    expect(oauth.userId, _keypairUserId, reason: 'user_id must not change');
    expect(oauth.hasKeypairFallback, isTrue);
    expect(oauth.provider, AuthProvider.google);

    expect(adapter.reconcileCount, 1);
    expect(
      telemetryRecords.any((r) => r.message.contains('accountUpgrade')),
      isTrue,
    );
    expect(
      container.read(upgradeInFlightProvider),
      isNull,
      reason: 'in-flight flag is cleared on success',
    );
  });

  test('post-reconcile step throwing does not downgrade a committed link',
      () async {
    // Re-wire the container with a telemetry that throws on accountUpgrade.
    // The reconcile (commit point) still succeeds, so the link is written
    // server-side; a trailing failure must not flip the state to failed.
    container.dispose();
    container = ProviderContainer(
      overrides: [
        cachedAuthSessionDaoProvider.overrideWithValue(db.cachedAuthSessionDao),
        supabaseAuthAdapterProvider.overrideWithValue(adapter),
        keypairStorageProvider.overrideWithValue(keypair),
        secureTokenStoreProvider.overrideWithValue(secureStore),
        authTelemetryProvider.overrideWithValue(_ThrowingTelemetry()),
      ],
    );
    adapter.reconcileUserId = _keypairUserId;

    await keypair.save(List<int>.filled(32, 7));
    await seedKeypairSession();
    await container.read(authControllerProvider.future);

    final notifier =
        container.read(accountUpgradeControllerProvider.notifier);
    await notifier.linkOAuth(AuthProvider.google);
    await notifier.completeLink(Uri.parse('kubbapp://auth/callback?code=abc'));

    expect(
      container.read(accountUpgradeControllerProvider),
      const AccountUpgradeState.done(),
      reason: 'a committed link must not report as failed',
    );
    expect(adapter.reconcileCount, 1);
    expect(container.read(upgradeInFlightProvider), isNull);
  });

  test('completeLink mapping a 409 surfaces failed(oauth_subject_in_use)',
      () async {
    await keypair.save(List<int>.filled(32, 7));
    await seedKeypairSession();
    await container.read(authControllerProvider.future);

    final notifier =
        container.read(accountUpgradeControllerProvider.notifier);
    await notifier.linkOAuth(AuthProvider.google);
    adapter.throwOnReconcile =
        const ReconcileException('oauth_subject_in_use');
    await notifier.completeLink(Uri.parse('kubbapp://auth/callback?code=abc'));

    expect(
      container.read(accountUpgradeControllerProvider),
      const AccountUpgradeState.failed(
        code: 'oauth_subject_in_use',
        provider: AuthProvider.google,
      ),
    );
    expect(container.read(upgradeInFlightProvider), isNull);
  });

  test('callback that never arrives times out into failed(callback_timeout)',
      () async {
    // Shrink the 3-minute window to a few ticks so the test does not
    // actually wait; the production default stays at 3 minutes.
    container.dispose();
    container = ProviderContainer(
      overrides: [
        cachedAuthSessionDaoProvider.overrideWithValue(db.cachedAuthSessionDao),
        supabaseAuthAdapterProvider.overrideWithValue(adapter),
        keypairStorageProvider.overrideWithValue(keypair),
        secureTokenStoreProvider.overrideWithValue(secureStore),
        authTelemetryProvider.overrideWithValue(AuthTelemetry()),
        upgradeCallbackTimeoutProvider
            .overrideWithValue(const Duration(milliseconds: 20)),
      ],
    );

    await keypair.save(List<int>.filled(32, 7));
    await seedKeypairSession();
    await container.read(authControllerProvider.future);

    await container
        .read(accountUpgradeControllerProvider.notifier)
        .linkOAuth(AuthProvider.google);
    expect(
      container.read(accountUpgradeControllerProvider),
      const AccountUpgradeState.awaitingCallback(AuthProvider.google),
    );

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(
      container.read(accountUpgradeControllerProvider),
      const AccountUpgradeState.failed(
        code: 'callback_timeout',
        provider: AuthProvider.google,
      ),
    );
  });
}
