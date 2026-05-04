import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    required List<int> ciphertext,
    required List<int> kdfSalt,
    required Map<String, Object> kdfParams,
    String? avatarColor,
  }) async {
    await _client.rpc<Map<String, dynamic>>(
      'keypair_attach',
      params: <String, dynamic>{
        'p_nickname': nickname,
        'p_public_key': base64Encode(publicKey),
        'p_ciphertext': base64Encode(ciphertext),
        'p_kdf_salt': base64Encode(kdfSalt),
        'p_kdf_params': kdfParams,
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
    final response = await _client.rpc<Map<String, dynamic>>(
      'keypair_challenge',
      params: <String, dynamic>{
        'p_public_key': base64Encode(publicKey),
      },
    );
    final encoded = response['challenge'] as String;
    return Uint8List.fromList(base64Decode(encoded));
  }

  @override
  Future<AuthVerifyResult> verifyKeypairSignature({
    required List<int> publicKey,
    required List<int> challenge,
    required List<int> signature,
  }) async {
    final response = await _client.rpc<Map<String, dynamic>>(
      'keypair_verify',
      params: <String, dynamic>{
        'p_public_key': base64Encode(publicKey),
        'p_challenge_b64': base64Encode(challenge),
        'p_signature_b64': base64Encode(signature),
      },
    );
    return AuthVerifyResult(
      userId: response['user_id'] as String,
      nickname: response['nickname'] as String,
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
