import 'dart:typed_data';

/// Provider used for OAuth sign-in. Apple is iOS-only at the UI layer
/// (per ADR-0010 §Klärung 3) but the data-layer enum carries it on
/// every platform so test code can exercise both branches.
enum AuthOAuthProvider { google, apple }

/// Snapshot of the auth session as the adapter sees it. The
/// application-layer `AuthSession` sealed class is built from these
/// values; the adapter does not know about that wrapper.
class AuthAdapterState {
  const AuthAdapterState({
    required this.userId,
    required this.kind,
    required this.expiresAt,
    this.refreshAfter,
    this.nickname,
  });

  const AuthAdapterState._signedOut()
      : userId = null,
        kind = AuthAdapterKind.signedOut,
        expiresAt = null,
        refreshAfter = null,
        nickname = null;

  /// Disconnected state — no session in the adapter.
  static const AuthAdapterState signedOut = AuthAdapterState._signedOut();

  final String? userId;
  final AuthAdapterKind kind;
  final DateTime? expiresAt;
  final DateTime? refreshAfter;
  final String? nickname;

  bool get isAuthenticated => kind != AuthAdapterKind.signedOut;
}

enum AuthAdapterKind {
  signedOut,
  anonymous,
  keypair,
  oauthGoogle,
  oauthApple,
}

/// Result of looking up an account by public-key challenge.
///
/// Carries the freshly minted access token so the caller can hydrate
/// the local Supabase session without a second round-trip. Phase 1
/// has no refresh token — when [expiresAt] passes the user signs in
/// again with the keypair (per ADR-0010 follow-up).
class AuthVerifyResult {
  const AuthVerifyResult({
    required this.userId,
    required this.nickname,
    required this.accessToken,
    required this.expiresAt,
  });
  final String userId;
  final String nickname;
  final String accessToken;
  final DateTime expiresAt;
}

/// Adapter contract over the Supabase auth surface. The real
/// implementation wraps `supabase_flutter`; tests use a fake.
///
/// Methods only handle the data-layer concerns (network calls, session
/// retrieval, OAuth flow kickoff). Higher-level orchestration —
/// "sign-up means: anonymous session + attach keypair + sync profile"
/// — lives in the application layer.
abstract class SupabaseAuthAdapter {
  /// Synchronous view of the current state. May lag behind the next
  /// emission of [onAuthStateChange] by a tick.
  AuthAdapterState get currentState;

  /// Stream of state changes. Emits the current state on subscribe.
  Stream<AuthAdapterState> get onAuthStateChange;

  /// Starts an OAuth sign-in. Returns once the browser tab / external
  /// app has been launched — the actual session lands later via
  /// [onAuthStateChange] when the deep-link / web callback fires.
  Future<void> signInWithOAuth(AuthOAuthProvider provider);

  /// Establishes an anonymous Supabase session via GoTrue's
  /// signInAnonymously. Required before [attachKeypair].
  Future<AuthAdapterState> signInAnonymously();

  /// Attaches a keypair credential plus encrypted backup to the
  /// currently-authenticated user (anonymous or otherwise). Returns
  /// the resulting state — typically the same userId, but with
  /// `kind = AuthAdapterKind.keypair`.
  Future<AuthAdapterState> attachKeypair({
    required String nickname,
    required List<int> publicKey,
    required List<int> ciphertext,
    required List<int> kdfSalt,
    required Map<String, Object> kdfParams,
    String? avatarColor,
  });

  /// Requests a fresh keypair challenge from the server.
  Future<Uint8List> requestKeypairChallenge(List<int> publicKey);

  /// Submits a signature to the server for verification.
  Future<AuthVerifyResult> verifyKeypairSignature({
    required List<int> publicKey,
    required List<int> challenge,
    required List<int> signature,
  });

  /// Adds an OAuth credential to the current user's account.
  Future<AuthAdapterState> linkOAuthToCurrentUser(AuthOAuthProvider provider);

  /// Hard-deletes the current user (cascades server-side per the
  /// auth.users CASCADE FKs).
  Future<void> deleteCurrentAccount();

  /// Ends the current session locally and remotely.
  Future<void> signOut();
}
