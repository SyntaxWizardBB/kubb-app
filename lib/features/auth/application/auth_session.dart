import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_session.freezed.dart';

/// Application-layer view of the authentication state. Independent
/// from the data-layer `AuthAdapterState` so the UI can pattern-match
/// without importing adapter types.
@freezed
class AuthSession with _$AuthSession {
  /// No session in flight. The router redirects here to /sign-in.
  const factory AuthSession.signedOut() = SignedOutSession;

  /// Anonymous Supabase session before a keypair has been attached.
  /// Reachable only during the AccountSetupController flow.
  const factory AuthSession.anonymous({required String userId}) =
      AnonymousSession;

  /// Authenticated via the anonymous keypair flow. After upgrading to
  /// OAuth (see [OAuthSession.hasKeypairFallback]), this state is
  /// replaced by an OAuth session that retains the keypair as a
  /// backup credential.
  const factory AuthSession.keypair({
    required String userId,
    required String displayName,
    String? avatarColor,
  }) = KeypairSession;

  /// Authenticated via OAuth.
  const factory AuthSession.oauth({
    required String userId,
    required String displayName,
    required AuthProvider provider,
    String? avatarColor,
    @Default(false) bool hasKeypairFallback,
  }) = OAuthSession;

  const AuthSession._();

  /// True when the session can be used to interact with cloud
  /// resources.
  bool get isAuthenticated => maybeWhen(
        signedOut: () => false,
        anonymous: (_) => false,
        orElse: () => true,
      );

  /// True when the session is the anonymous-keypair-only path.
  bool get isAnonymousKeypair => maybeWhen(
        keypair: (_, _, _) => true,
        orElse: () => false,
      );

  /// User id behind the session if any.
  String? get userId => maybeWhen(
        signedOut: () => null,
        anonymous: (id) => id,
        keypair: (id, _, _) => id,
        oauth: (id, _, _, _, _) => id,
        orElse: () => null,
      );

  /// Display name for the UI; null on signed-out / pre-attach.
  String? get displayName => maybeWhen(
        keypair: (_, name, _) => name,
        oauth: (_, name, _, _, _) => name,
        orElse: () => null,
      );
}

/// OAuth provider identifier exposed to the application layer. Mirror
/// of the data-layer enum but lives here to keep the application
/// independent.
enum AuthProvider { google, apple }
