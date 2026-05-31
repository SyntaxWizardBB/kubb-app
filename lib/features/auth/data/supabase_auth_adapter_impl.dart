import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Same anon key bootstrap passes to `Supabase.initialize` (via
/// `--dart-define`). Used to authorize the pre-auth `keypair_challenge`
/// RPC with the anon role instead of a possibly-expired session bearer.
const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Production [SupabaseAuthAdapter] backed by the `supabase_flutter`
/// SDK.
///
/// Construction takes the [SupabaseClient] explicitly so application
/// bootstrap owns Supabase.initialize and the adapter stays
/// constructor-injectable. Application-layer tests drive
/// `FakeSupabaseAuthAdapter` instead of trying to mock the SDK.
class SupabaseAuthAdapterImpl implements SupabaseAuthAdapter {
  SupabaseAuthAdapterImpl(this._client) {
    _state = _stateFromSession(_client.auth.currentSession);
    _sub = _client.auth.onAuthStateChange.listen((event) {
      _state = _stateFromSession(event.session);
      _controller.add(_state);
    });
  }

  final SupabaseClient _client;
  late AuthAdapterState _state;
  late final StreamSubscription<AuthState> _sub;
  final StreamController<AuthAdapterState> _controller =
      StreamController<AuthAdapterState>.broadcast();

  @override
  AuthAdapterState get currentState => _state;

  @override
  Stream<AuthAdapterState> get onAuthStateChange async* {
    yield _state;
    yield* _controller.stream;
  }

  @override
  String? get wireAccessToken => _client.auth.currentSession?.accessToken;

  @override
  Future<AuthAdapterState> refreshSession() async {
    final response = await _client.auth.refreshSession();
    _state = _stateFromSession(response.session);
    _controller.add(_state);
    return _state;
  }

  @override
  Future<void> signInWithOAuth(AuthOAuthProvider provider) async {
    await _client.auth.signInWithOAuth(
      provider == AuthOAuthProvider.google
          ? OAuthProvider.google
          : OAuthProvider.apple,
      redirectTo: 'kubbapp://auth/callback',
    );
  }

  @override
  Future<AuthAdapterState> signInAnonymously() async {
    final response = await _client.auth.signInAnonymously();
    _state = _stateFromSession(response.session);
    _controller.add(_state);
    return _state;
  }

  @override
  Future<AuthAdapterState> attachKeypair({
    required String nickname,
    required List<int> publicKey,
    required String earlyAccessCode,
    String? avatarColor,
  }) async {
    await _client.rpc<Map<String, dynamic>>(
      'keypair_register',
      params: <String, dynamic>{
        'p_nickname': nickname,
        'p_public_key': base64Encode(publicKey),
        'p_early_access_code': earlyAccessCode,
        'p_avatar_color': avatarColor,
      },
    );
    final base = _state;
    _state = AuthAdapterState(
      userId: base.userId,
      kind: AuthAdapterKind.keypair,
      expiresAt: base.expiresAt,
      refreshAfter: base.refreshAfter,
      nickname: nickname,
    );
    _controller.add(_state);
    return _state;
  }

  @override
  Future<Uint8List> requestKeypairChallenge(List<int> publicKey) async {
    final builder = _client.rpc<Map<String, dynamic>>(
      'keypair_challenge',
      params: <String, dynamic>{
        'p_public_key': base64Encode(publicKey),
      },
    );
    // The keypair re-sign runs precisely when the wire token has expired.
    // supabase_flutter still attaches that stale (expired) bearer to this
    // anon-callable RPC, so PostgREST rejects it with PGRST303 ("JWT
    // expired") before the function runs — which permanently blocks
    // re-minting (the recovery can never fetch a challenge). Pin the anon
    // key for this single call so a challenge is always obtainable.
    // keypair_challenge is GRANTed to anon; keypair-verify has
    // verify_jwt = false, so the verify step is unaffected by the stale token.
    final response = _anonKey.isEmpty
        ? await builder
        : await builder.setHeader('Authorization', 'Bearer $_anonKey');
    final encoded = response['challenge'] as String;
    return Uint8List.fromList(base64Decode(encoded));
  }

  @override
  Future<AuthVerifyResult> verifyKeypairSignature({
    required List<int> publicKey,
    required List<int> challenge,
    required List<int> signature,
  }) async {
    // Verify runs in the keypair-verify edge function (M8-T01) — Postgres
    // has no built-in Ed25519, so the previous SECURITY DEFINER stub
    // never actually checked the signature. The function lives at
    // supabase/functions/keypair-verify/.
    //
    // Since M8-T03 the function also mints the access token, so this
    // call is a one-shot: on success we hydrate the local gotrue
    // session via recoverSession and the adapter's auth-state stream
    // emits the new authenticated state.
    final response = await _client.functions.invoke(
      'keypair-verify',
      body: <String, dynamic>{
        'public_key': base64Encode(publicKey),
        'challenge_b64': base64Encode(challenge),
        'signature_b64': base64Encode(signature),
      },
    );
    if (response.status < 200 || response.status >= 300) {
      final detail = response.data is Map<String, dynamic>
          ? (response.data as Map<String, dynamic>)['error']
          : response.data;
      throw StateError(
        'keypair-verify failed (status ${response.status}): $detail',
      );
    }
    final data = response.data as Map<String, dynamic>;
    final userId = data['user_id'] as String;
    final nickname = data['nickname'] as String;
    final accessToken = data['access_token'] as String;
    final expiresAtUnix = (data['expires_at'] as num).toInt();
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      expiresAtUnix * 1000,
      isUtc: true,
    );

    // Hydrate the local session. The Phase-1 token has no refresh
    // counterpart, so we hand gotrue a self-contained Session JSON via
    // recoverSession instead of setSession (which insists on a
    // non-empty refresh_token). `_saveSession` runs internally and the
    // tokenRefreshed event flows through to onAuthStateChange — our
    // own listener picks it up and updates _state.
    final sessionJson = jsonEncode(<String, dynamic>{
      'access_token': accessToken,
      'token_type': 'bearer',
      'expires_in': expiresAtUnix - DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'expires_at': expiresAtUnix,
      'user': <String, dynamic>{
        'id': userId,
        'aud': 'authenticated',
        'role': 'authenticated',
        'app_metadata': <String, dynamic>{
          'provider': 'keypair',
          'providers': <String>['keypair'],
        },
        'user_metadata': <String, dynamic>{'nickname': nickname},
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_anonymous': false,
      },
    });
    await _client.auth.recoverSession(sessionJson);

    return AuthVerifyResult(
      userId: userId,
      nickname: nickname,
      accessToken: accessToken,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<AuthAdapterState> linkOAuthToCurrentUser(
      AuthOAuthProvider provider) async {
    // Supabase exposes linkIdentity for adding OAuth credentials to an
    // existing user. After completion the auth-state stream emits the
    // upgraded session.
    await _client.auth.linkIdentity(
      provider == AuthOAuthProvider.google
          ? OAuthProvider.google
          : OAuthProvider.apple,
      redirectTo: 'kubbapp://auth/callback',
    );
    return _state;
  }

  @override
  Future<void> deleteCurrentAccount() async {
    // Server-side SECURITY DEFINER function deletes the row in
    // auth.users for the current JWT subject and cascades through the
    // user_credentials / user_keypair_backups / user_profiles FKs.
    // Calling admin.deleteUser from the mobile client would require
    // the service-role key in the app bundle — never acceptable.
    await _client.rpc<void>('fn_delete_current_account');
    await _client.auth.signOut();
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  AuthAdapterState _stateFromSession(Session? session) {
    if (session == null) return AuthAdapterState.signedOut;
    final user = session.user;
    final kind = _kindForUser(user);
    return AuthAdapterState(
      userId: user.id,
      kind: kind,
      expiresAt: session.expiresAt != null
          ? DateTime.fromMillisecondsSinceEpoch(
              session.expiresAt! * 1000,
              isUtc: true,
            )
          : null,
      refreshAfter: session.expiresAt != null
          ? DateTime.fromMillisecondsSinceEpoch(
              session.expiresAt! * 1000,
              isUtc: true,
            ).subtract(const Duration(minutes: 5))
          : null,
      nickname: user.userMetadata?['nickname'] as String?,
    );
  }

  AuthAdapterKind _kindForUser(User user) {
    final identities = user.identities ?? const <UserIdentity>[];
    for (final identity in identities) {
      switch (identity.provider) {
        case 'google':
          return AuthAdapterKind.oauthGoogle;
        case 'apple':
          return AuthAdapterKind.oauthApple;
      }
    }
    if (user.isAnonymous) return AuthAdapterKind.anonymous;
    // Fallback: if there is a session but neither OAuth nor anonymous,
    // assume it was promoted via keypair_attach.
    return AuthAdapterKind.keypair;
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await _controller.close();
  }
}
