import 'dart:async';
import 'dart:typed_data';

import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';

/// Deterministic in-memory implementation of [SupabaseAuthAdapter] for
/// tests. Tracks state, emits via [onAuthStateChange], and lets test
/// cases inject canned responses (challenges, verify results) and
/// failures via override hooks.
class FakeSupabaseAuthAdapter implements SupabaseAuthAdapter {
  FakeSupabaseAuthAdapter() {
    _state = AuthAdapterState.signedOut;
    _controller = StreamController<AuthAdapterState>.broadcast(
      onListen: () => _controller.add(_state),
    );
  }

  late AuthAdapterState _state;
  late final StreamController<AuthAdapterState> _controller;

  /// If non-null, the next [requestKeypairChallenge] returns this
  /// instead of a deterministic generated challenge.
  Uint8List? challengeOverride;

  /// If non-null, the next [verifyKeypairSignature] returns this.
  AuthVerifyResult? verifyOverride;

  /// If non-null, the next [signInWithOAuth] / [signInAnonymously] /
  /// [attachKeypair] / [linkOAuthToCurrentUser] / [signOut] /
  /// [deleteCurrentAccount] / [verifyKeypairSignature] /
  /// [requestKeypairChallenge] throws this and clears the field.
  Object? throwOnNextCall;

  /// Counter exposed for tests that want to assert "called exactly N
  /// times" without going through mocktail.
  int signOutCount = 0;
  int deleteAccountCount = 0;
  int oauthCount = 0;
  int anonymousCount = 0;
  int attachKeypairCount = 0;
  int linkOAuthCount = 0;
  int refreshSessionCount = 0;

  /// Controls what [wireAccessToken] returns. Tests can set this to
  /// `null` to simulate the cache-hydrated-but-wire-empty drift
  /// scenario from R1-F-02 / Mängel #9.
  String? wireAccessTokenOverride = 'fake-wire-token';

  /// When non-null, the next [refreshSession] swaps the wire token in
  /// for [wireAccessTokenOverride] and emits the matching state.
  String? refreshTokenResult = 'fake-refreshed-wire-token';

  void _maybeThrow() {
    final t = throwOnNextCall;
    if (t != null) {
      throwOnNextCall = null;
      // Test fixture rethrows whatever the test asked us to throw,
      // including domain-specific value types that do not extend Error.
      // ignore: only_throw_errors
      throw t;
    }
  }

  void _emit(AuthAdapterState next) {
    _state = next;
    _controller.add(next);
  }

  @override
  AuthAdapterState get currentState => _state;

  @override
  Stream<AuthAdapterState> get onAuthStateChange => _controller.stream;

  @override
  String? get wireAccessToken => wireAccessTokenOverride;

  @override
  Future<AuthAdapterState> refreshSession() async {
    _maybeThrow();
    refreshSessionCount += 1;
    wireAccessTokenOverride = refreshTokenResult;
    // Re-emit the current state so any listener wakes up.
    _controller.add(_state);
    return _state;
  }

  @override
  Future<void> signInWithOAuth(AuthOAuthProvider provider) async {
    _maybeThrow();
    oauthCount += 1;
    final now = DateTime.now().toUtc();
    _emit(AuthAdapterState(
      userId: 'fake-user-${provider.name}',
      kind: provider == AuthOAuthProvider.google
          ? AuthAdapterKind.oauthGoogle
          : AuthAdapterKind.oauthApple,
      expiresAt: now.add(const Duration(hours: 1)),
      refreshAfter: now.add(const Duration(minutes: 50)),
      nickname: provider.name,
    ));
  }

  @override
  Future<AuthAdapterState> signInAnonymously() async {
    _maybeThrow();
    anonymousCount += 1;
    final now = DateTime.now().toUtc();
    _emit(AuthAdapterState(
      userId: 'fake-anon-$anonymousCount',
      kind: AuthAdapterKind.anonymous,
      expiresAt: now.add(const Duration(hours: 1)),
      refreshAfter: now.add(const Duration(minutes: 50)),
    ));
    return _state;
  }

  @override
  Future<AuthAdapterState> attachKeypair({
    required String nickname,
    required List<int> publicKey,
    String? avatarColor,
  }) async {
    _maybeThrow();
    attachKeypairCount += 1;
    if (_state.userId == null) {
      throw StateError('attachKeypair requires an active session');
    }
    _emit(AuthAdapterState(
      userId: _state.userId,
      kind: AuthAdapterKind.keypair,
      expiresAt: _state.expiresAt,
      refreshAfter: _state.refreshAfter,
      nickname: nickname,
    ));
    return _state;
  }

  @override
  Future<Uint8List> requestKeypairChallenge(List<int> publicKey) async {
    _maybeThrow();
    if (challengeOverride != null) return challengeOverride!;
    // Deterministic-but-distinct: the first byte is the call counter,
    // the rest are derived from the public key.
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = (publicKey[i % publicKey.length] + i) & 0xff;
    }
    return out;
  }

  @override
  Future<AuthVerifyResult> verifyKeypairSignature({
    required List<int> publicKey,
    required List<int> challenge,
    required List<int> signature,
  }) async {
    _maybeThrow();
    final result = verifyOverride ??
        AuthVerifyResult(
          userId: 'fake-verified-user',
          nickname: 'fake-nick',
          accessToken: 'fake-access-token',
          expiresAt:
              DateTime.now().toUtc().add(const Duration(hours: 1)),
        );
    // Hydrate the in-memory session the same way the real adapter does
    // via recoverSession — tests downstream of restore expect a live
    // keypair session (matching userId) to land in onAuthStateChange.
    final now = DateTime.now().toUtc();
    _emit(AuthAdapterState(
      userId: result.userId,
      kind: AuthAdapterKind.keypair,
      expiresAt: result.expiresAt,
      refreshAfter: now.add(const Duration(minutes: 50)),
      nickname: result.nickname,
    ));
    return result;
  }

  @override
  Future<AuthAdapterState> linkOAuthToCurrentUser(
      AuthOAuthProvider provider) async {
    _maybeThrow();
    linkOAuthCount += 1;
    if (_state.userId == null) {
      throw StateError('linkOAuth requires an active session');
    }
    _emit(AuthAdapterState(
      userId: _state.userId,
      kind: provider == AuthOAuthProvider.google
          ? AuthAdapterKind.oauthGoogle
          : AuthAdapterKind.oauthApple,
      expiresAt: _state.expiresAt,
      refreshAfter: _state.refreshAfter,
      nickname: _state.nickname,
    ));
    return _state;
  }

  @override
  Future<void> deleteCurrentAccount() async {
    _maybeThrow();
    deleteAccountCount += 1;
    _emit(AuthAdapterState.signedOut);
  }

  @override
  Future<void> signOut() async {
    _maybeThrow();
    signOutCount += 1;
    _emit(AuthAdapterState.signedOut);
  }

  Future<void> dispose() => _controller.close();
}
