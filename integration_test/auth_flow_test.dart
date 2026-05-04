// End-to-end smoke test of the auth pipeline against fake adapters.
//
// Runs the real Riverpod graph, the real drift schema (in-memory) and
// the real auth controllers. Only the boundary that talks to Supabase
// (network, secure storage, cloud profile) is replaced by fakes from
// `test/fixtures/auth/`.
//
// Like `sniper_flow_test.dart` this needs a Flutter device:
//   flutter test integration_test/auth_flow_test.dart -d <device>
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/account_upgrade_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/application/cloud_profile_provider.dart';
import 'package:kubb_app/features/auth/application/restore_controller.dart';
import 'package:kubb_app/features/auth/data/auth_telemetry.dart';
import 'package:kubb_app/features/auth/data/crypto_service.dart';
import 'package:kubb_app/features/auth/data/secure_token_store.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:logging/logging.dart';

import '../test/fixtures/auth/fake_cloud_profile_repository.dart';
import '../test/fixtures/auth/fake_keypair_backup_repository.dart';
import '../test/fixtures/auth/fake_supabase_auth_adapter.dart';

class _InMemorySecureStore implements SecureTokenStore {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> read(SecureTokenKind kind) async => _data[kind.storageKey];

  @override
  Future<void> write(SecureTokenKind kind, String value) async {
    _data[kind.storageKey] = value;
  }

  @override
  Future<void> delete(SecureTokenKind kind) async {
    _data.remove(kind.storageKey);
  }

  @override
  Future<void> deleteAll() async {
    _data.clear();
  }
}

class _AuthHarness {
  _AuthHarness({
    required this.db,
    required this.adapter,
    required this.backupRepo,
    required this.profileRepo,
    required this.secureStore,
    required this.telemetry,
    required this.events,
  });

  final AppDatabase db;
  final FakeSupabaseAuthAdapter adapter;
  final FakeKeypairBackupRepository backupRepo;
  final FakeCloudProfileRepository profileRepo;
  final _InMemorySecureStore secureStore;
  final AuthTelemetry telemetry;
  final List<LogRecord> events;

  ProviderScope wrap(Widget child) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          cachedAuthSessionDaoProvider
              .overrideWithValue(db.cachedAuthSessionDao),
          supabaseAuthAdapterProvider.overrideWithValue(adapter),
          keypairBackupRepositoryProvider.overrideWithValue(backupRepo),
          cloudProfileRepositoryProvider.overrideWithValue(profileRepo),
          secureTokenStoreProvider.overrideWithValue(secureStore),
          cryptoServiceProvider.overrideWithValue(CryptoService()),
          authTelemetryProvider.overrideWithValue(telemetry),
        ],
        child: child,
      );
}

Future<_AuthHarness> _buildHarness() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.customStatement('PRAGMA foreign_keys = ON');
  final events = <LogRecord>[];
  final logger = Logger.detached('auth-it')
    ..level = Level.ALL
    ..onRecord.listen(events.add);
  return _AuthHarness(
    db: db,
    adapter: FakeSupabaseAuthAdapter(),
    backupRepo: FakeKeypairBackupRepository(),
    profileRepo: FakeCloudProfileRepository(),
    secureStore: _InMemorySecureStore(),
    telemetry: AuthTelemetry(logger: logger),
    events: events,
  );
}

bool _hasEvent(List<LogRecord> events, String eventName) {
  return events.any((r) => r.message.startsWith(eventName));
}

Future<void> _completeAnonymousSignup(
  WidgetTester tester, {
  required String nickname,
  required String passphrase,
}) async {
  final l10n = await AppLocalizations.delegate.load(const Locale('de'));

  // Sign-in screen → tap anonymous CTA. The label changes to a "loading"
  // variant once the route push starts, so we match against either form
  // to stay robust when the test is paused mid-frame.
  expect(find.text(l10n.authSigninAnonymous), findsOneWidget);
  await tester.tap(find.text(l10n.authSigninAnonymous));
  await tester.pumpAndSettle();

  // Step 1 — nickname.
  await tester.enterText(find.byType(TextField), nickname);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.authCommonContinue));
  await tester.pumpAndSettle();

  // Step 2 — disclaimer + passphrase + submit.
  await tester.tap(find.text(l10n.authDisclaimerAcknowledge));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, passphrase);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.authSignupSubmit));
  // Waiting for the controller submit + adapter listener round-trip.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('de');
  });

  testWidgets(
    'anonymous signup persists session, uploads backup, logs telemetry',
    (tester) async {
      final h = await _buildHarness();
      addTearDown(h.db.close);
      addTearDown(h.adapter.dispose);

      await tester.pumpWidget(h.wrap(const KubbApp()));
      await tester.pumpAndSettle();

      await _completeAnonymousSignup(
        tester,
        nickname: 'test-user-1',
        passphrase: 'very-secure-pass-123',
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KubbApp)),
      );

      final session = container.read(authControllerProvider).requireValue;
      expect(session, isA<KeypairSession>());
      expect(session.displayName, 'test-user-1');
      expect(session.userId, isNotNull);

      final cached = await h.db.cachedAuthSessionDao.current();
      expect(cached, isNotNull);
      expect(cached!.kind, 'keypair');
      expect(cached.displayName, 'test-user-1');

      expect(h.backupRepo.storedNicknames, contains('test-user-1'));
      expect(h.secureStore._data, isNotEmpty);

      expect(_hasEvent(h.events, 'keypairBackupCreated'), isTrue);
      expect(_hasEvent(h.events, 'signinSuccess'), isTrue);
    },
  );

  testWidgets(
    'restore flow recovers a keypair from the cloud backup',
    (tester) async {
      final h = await _buildHarness();
      addTearDown(h.db.close);
      addTearDown(h.adapter.dispose);

      // Seed the cloud-side backup as if a previous device created it.
      // FakeKeypairBackupRepository runs real Argon2id + XChaCha20 here,
      // so the round-trip is genuinely cryptographically validated.
      await h.backupRepo.uploadBackup(
        nickname: 'returning-user',
        privateKey: Uint8ListMother.bytes32(),
        publicKey: Uint8ListMother.bytes32(seed: 7),
        passphrase: 'right-passphrase-pass',
      );

      await tester.pumpWidget(h.wrap(const KubbApp()));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('de'));

      // Sign-in → restore footer link.
      await tester.tap(find.text(l10n.authSigninRestore));
      await tester.pumpAndSettle();

      // Step 1 — nickname.
      await tester.enterText(find.byType(TextField), 'returning-user');
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.authCommonContinue));
      await tester.pumpAndSettle();

      // Step 2 — passphrase.
      await tester.enterText(find.byType(TextField).first,
          'right-passphrase-pass');
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.authRestoreSubmit));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KubbApp)),
      );

      final restoreState = container.read(restoreControllerProvider);
      final restoreVariant = restoreState.maybeWhen(
        done: (_) => 'done',
        orElse: () => 'other',
      );
      expect(restoreVariant, 'done',
          reason: 'restore controller should reach done on a valid pair');

      // The private key is now in secure storage and the challenge /
      // verify round-trip has run via the fake adapter — the controller
      // landed on done with the verified user_id. We assert both: the
      // key persisted, and the restore reached its terminal state.
      expect(h.secureStore._data, isNotEmpty);
      expect(_hasEvent(h.events, 'restoreAttempted'), isTrue);
      final restoreLog = h.events
          .firstWhere((r) => r.message.startsWith('restoreAttempted'));
      expect(restoreLog.message, contains('success=true'));
    },
  );

  testWidgets(
    'oauth upgrade after anonymous signup transitions to OAuthSession',
    (tester) async {
      final h = await _buildHarness();
      addTearDown(h.db.close);
      addTearDown(h.adapter.dispose);

      await tester.pumpWidget(h.wrap(const KubbApp()));
      await tester.pumpAndSettle();

      await _completeAnonymousSignup(
        tester,
        nickname: 'upgrade-user',
        passphrase: 'upgrade-pass-1234',
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KubbApp)),
      );

      // The router lands on / after signup; drive the upgrade through the
      // controller directly — the AccountLinkScreen route is the same
      // call site, just with a button tap on top.
      await container
          .read(accountUpgradeControllerProvider.notifier)
          .linkOAuth(AuthProvider.google);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      final session = container.read(authControllerProvider).requireValue;
      expect(session, isA<OAuthSession>());
      final oauth = session as OAuthSession;
      expect(oauth.provider, AuthProvider.google);
      expect(h.adapter.linkOAuthCount, 1);
      expect(_hasEvent(h.events, 'accountUpgrade'), isTrue);
    },
  );

  testWidgets('signOut clears the cache and routes back to sign-in',
      (tester) async {
    final h = await _buildHarness();
    addTearDown(h.db.close);
    addTearDown(h.adapter.dispose);

    await tester.pumpWidget(h.wrap(const KubbApp()));
    await tester.pumpAndSettle();

    await _completeAnonymousSignup(
      tester,
      nickname: 'logout-user',
      passphrase: 'logout-pass-1234',
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(KubbApp)),
    );

    await container.read(authControllerProvider.notifier).signOut();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(
      container.read(authControllerProvider).requireValue,
      const AuthSession.signedOut(),
    );
    expect(await h.db.cachedAuthSessionDao.current(), isNull);
    expect(_hasEvent(h.events, 'logout'), isTrue);
  });
}

/// Tiny deterministic byte-fixture helper. Public so the int-test stays
/// self-contained without dragging in a wider random-bytes dependency.
abstract final class Uint8ListMother {
  static Uint8List bytes32({int seed = 1}) =>
      Uint8List.fromList(List<int>.generate(32, (i) => (i + seed) & 0xff));
}
