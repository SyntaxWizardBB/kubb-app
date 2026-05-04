import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';

import '../../../fixtures/auth/fake_supabase_auth_adapter.dart';

/// Contract tests against the [SupabaseAuthAdapter] interface, exercised
/// via [FakeSupabaseAuthAdapter]. The real adapter (M3-T02) implements
/// the same contract and re-runs this suite.
void main() {
  late FakeSupabaseAuthAdapter adapter;

  setUp(() {
    adapter = FakeSupabaseAuthAdapter();
  });

  tearDown(() async {
    await adapter.dispose();
  });

  test('starts in signed-out state', () {
    expect(adapter.currentState.kind, AuthAdapterKind.signedOut);
    expect(adapter.currentState.isAuthenticated, isFalse);
    expect(adapter.currentState.userId, isNull);
  });

  test('onAuthStateChange emits the current state on subscribe', () async {
    final received = <AuthAdapterState>[];
    final sub = adapter.onAuthStateChange.listen(received.add);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(received.length, 1);
    expect(received.first.kind, AuthAdapterKind.signedOut);

    await sub.cancel();
  });

  test('signInAnonymously transitions to anonymous state', () async {
    final state = await adapter.signInAnonymously();

    expect(state.kind, AuthAdapterKind.anonymous);
    expect(state.userId, isNotNull);
    expect(state.expiresAt, isNotNull);
    expect(adapter.currentState.kind, AuthAdapterKind.anonymous);
  });

  test('signInWithOAuth(google) transitions to oauthGoogle state',
      () async {
    await adapter.signInWithOAuth(AuthOAuthProvider.google);

    expect(adapter.currentState.kind, AuthAdapterKind.oauthGoogle);
    expect(adapter.currentState.isAuthenticated, isTrue);
  });

  test('signInWithOAuth(apple) transitions to oauthApple state', () async {
    await adapter.signInWithOAuth(AuthOAuthProvider.apple);

    expect(adapter.currentState.kind, AuthAdapterKind.oauthApple);
  });

  test('attachKeypair requires an active session', () async {
    await expectLater(
      adapter.attachKeypair(
        nickname: 'lukas',
        publicKey: const [1, 2, 3],
        ciphertext: const [4, 5, 6],
        kdfSalt: const [7, 8, 9],
        kdfParams: const {'algo': 'argon2id'},
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('attachKeypair upgrades anonymous session to keypair', () async {
    final anon = await adapter.signInAnonymously();
    final after = await adapter.attachKeypair(
      nickname: 'lukas',
      publicKey: const [1, 2, 3],
      ciphertext: const [4, 5, 6],
      kdfSalt: const [7, 8, 9],
      kdfParams: const {'algo': 'argon2id'},
    );

    expect(after.userId, anon.userId);
    expect(after.kind, AuthAdapterKind.keypair);
    expect(after.nickname, 'lukas');
  });

  test('requestKeypairChallenge returns a 32-byte challenge', () async {
    final challenge = await adapter.requestKeypairChallenge(
      Uint8List.fromList(List.generate(32, (i) => i)),
    );
    expect(challenge.length, 32);
  });

  test('verifyKeypairSignature returns the verified user identity',
      () async {
    final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 1));
    adapter.verifyOverride = AuthVerifyResult(
      userId: 'restored-user-id',
      nickname: 'lukas',
      accessToken: 'access.jwt.token',
      expiresAt: expiresAt,
    );
    final result = await adapter.verifyKeypairSignature(
      publicKey: const [1, 2],
      challenge: const [3, 4],
      signature: const [5, 6],
    );
    expect(result.userId, 'restored-user-id');
    expect(result.nickname, 'lukas');
    expect(result.accessToken, 'access.jwt.token');
    expect(result.expiresAt, expiresAt);
  });

  test('verifyKeypairSignature hydrates a keypair session', () async {
    adapter.verifyOverride = AuthVerifyResult(
      userId: 'restored-user-id',
      nickname: 'lukas',
      accessToken: 'access.jwt.token',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await adapter.verifyKeypairSignature(
      publicKey: const [1, 2],
      challenge: const [3, 4],
      signature: const [5, 6],
    );
    expect(adapter.currentState.kind, AuthAdapterKind.keypair);
    expect(adapter.currentState.userId, 'restored-user-id');
    expect(adapter.currentState.nickname, 'lukas');
  });

  test('linkOAuthToCurrentUser keeps the same user_id', () async {
    final keypairUser =
        await adapter.signInAnonymously().then((_) => adapter.attachKeypair(
              nickname: 'lukas',
              publicKey: const [1, 2, 3],
              ciphertext: const [4, 5, 6],
              kdfSalt: const [7, 8, 9],
              kdfParams: const {'algo': 'argon2id'},
            ));

    final after = await adapter
        .linkOAuthToCurrentUser(AuthOAuthProvider.google);

    expect(after.userId, keypairUser.userId);
    expect(after.kind, AuthAdapterKind.oauthGoogle);
  });

  test('signOut returns to signedOut and emits the change', () async {
    await adapter.signInAnonymously();
    expect(adapter.currentState.kind, AuthAdapterKind.anonymous);

    final received = <AuthAdapterState>[];
    final sub = adapter.onAuthStateChange.listen(received.add);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await adapter.signOut();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(adapter.currentState.kind, AuthAdapterKind.signedOut);
    // received contains: initial-anon-on-subscribe, signed-out-emit
    expect(received.last.kind, AuthAdapterKind.signedOut);

    await sub.cancel();
  });

  test('deleteCurrentAccount drops the session', () async {
    await adapter.signInAnonymously();
    await adapter.deleteCurrentAccount();

    expect(adapter.currentState.kind, AuthAdapterKind.signedOut);
    expect(adapter.deleteAccountCount, 1);
  });

  test('throwOnNextCall surfaces the configured error once', () async {
    adapter.throwOnNextCall = StateError('network down');

    await expectLater(
      adapter.signInAnonymously(),
      throwsA(isA<StateError>()),
    );

    // Next call should succeed — the override is single-use.
    final state = await adapter.signInAnonymously();
    expect(state.kind, AuthAdapterKind.anonymous);
  });
}
