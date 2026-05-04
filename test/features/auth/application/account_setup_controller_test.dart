import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/data/auth_telemetry.dart';
import 'package:kubb_app/features/auth/data/crypto_service.dart';
import 'package:kubb_app/features/auth/data/secure_token_store.dart';

import '../../../fixtures/auth/fake_keypair_backup_repository.dart';
import '../../../fixtures/auth/fake_supabase_auth_adapter.dart';

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

void main() {
  late FakeSupabaseAuthAdapter adapter;
  late FakeKeypairBackupRepository backup;
  late _InMemorySecureStore secure;
  late ProviderContainer container;

  setUp(() {
    adapter = FakeSupabaseAuthAdapter();
    backup = FakeKeypairBackupRepository();
    secure = _InMemorySecureStore();
    container = ProviderContainer(
      overrides: [
        supabaseAuthAdapterProvider.overrideWithValue(adapter),
        authTelemetryProvider.overrideWithValue(AuthTelemetry()),
        keypairBackupRepositoryProvider.overrideWithValue(backup),
        secureTokenStoreProvider.overrideWithValue(secure),
        cryptoServiceProvider.overrideWithValue(CryptoService()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await adapter.dispose();
  });

  test('initial state is idle', () {
    expect(
      container.read(accountSetupControllerProvider),
      const AccountSetupState.idle(),
    );
  });

  test('setNickname transitions to nicknameEntered', () {
    container
        .read(accountSetupControllerProvider.notifier)
        .setNickname('lukas');

    expect(
      container.read(accountSetupControllerProvider),
      const AccountSetupState.nicknameEntered(nickname: 'lukas'),
    );
  });

  test('submit happy-path flows through anonymous → attach → backup → done',
      () async {
    await container.read(accountSetupControllerProvider.notifier).submit(
          nickname: 'lukas',
          passphrase: 'correct-horse-battery',
        );

    final state = container.read(accountSetupControllerProvider);
    final variant = state.maybeWhen(
      done: (userId) => 'done:$userId',
      orElse: () => 'other',
    );
    expect(variant, startsWith('done:'));
    expect(adapter.anonymousCount, 1);
    expect(adapter.attachKeypairCount, 1);
    expect(backup.storedNicknames, contains('lukas'));
  });

  test('submit failure surfaces as failed with reason', () async {
    adapter.throwOnNextCall = StateError('network down');

    await container.read(accountSetupControllerProvider.notifier).submit(
          nickname: 'lukas',
          passphrase: 'pp',
        );

    final state = container.read(accountSetupControllerProvider);
    final reason = state.maybeWhen(
      failed: (r) => r,
      orElse: () => null,
    );
    expect(reason, isNotNull);
    expect(adapter.attachKeypairCount, 0);
    expect(backup.storedNicknames, isEmpty);
  });

  test('submit private-key is persisted to secure storage', () async {
    await container.read(accountSetupControllerProvider.notifier).submit(
          nickname: 'lukas',
          passphrase: 'pp',
        );

    expect(
      await secure.read(SecureTokenKind.privateKey),
      isNotNull,
      reason: 'private key must land in secure storage on success',
    );
  });
}
