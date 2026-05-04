import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/data/auth_telemetry.dart';
import 'package:kubb_app/features/auth/data/dao/cached_auth_session_dao.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Production [SupabaseAuthAdapter] backed by the live Supabase
/// client. Tests override this with a fake.
final supabaseAuthAdapterProvider = Provider<SupabaseAuthAdapter>((ref) {
  return SupabaseAuthAdapterImpl(Supabase.instance.client);
});

/// DAO over the cached_auth_session table. Tests override with an
/// in-memory drift instance.
final cachedAuthSessionDaoProvider = Provider<CachedAuthSessionDao>((ref) {
  throw UnimplementedError(
    'cachedAuthSessionDaoProvider must be overridden during app '
    'bootstrap with the real CachedAuthSessionDao instance.',
  );
});

final authTelemetryProvider = Provider<AuthTelemetry>((ref) {
  return AuthTelemetry();
});

/// Central [AuthSession] state. Application widgets watch this; the
/// router watches it for redirect decisions.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession>(AuthController.new);

/// Riverpod-side AsyncNotifier for the active [AuthSession].
///
/// Boot path:
///   1. Read the cached session from drift — synchronous-ish (a single
///      drift query). If present, emit the corresponding AuthSession
///      and refresh state will arrive when the adapter emits.
///   2. Subscribe to [SupabaseAuthAdapter.onAuthStateChange] and map
///      every emission to an AuthSession. Persist into the DAO and
///      emit telemetry.
///
/// Sign-out clears both the DAO and the adapter, then emits SignedOut.
class AuthController extends AsyncNotifier<AuthSession> {
  StreamSubscription<AuthAdapterState>? _sub;

  SupabaseAuthAdapter get _adapter =>
      ref.read(supabaseAuthAdapterProvider);
  CachedAuthSessionDao get _dao =>
      ref.read(cachedAuthSessionDaoProvider);
  AuthTelemetry get _telemetry => ref.read(authTelemetryProvider);

  @override
  Future<AuthSession> build() async {
    ref.onDispose(() => _sub?.cancel());
    _sub = _adapter.onAuthStateChange.listen(_onAdapterState);

    final cached = await _dao.current();
    if (cached != null) {
      return _sessionFromCache(cached);
    }
    final adapterState = _adapter.currentState;
    if (adapterState.isAuthenticated) {
      return _sessionFromAdapter(adapterState);
    }
    return const AuthSession.signedOut();
  }

  Future<void> signOut() async {
    final userId = state.value?.userId;
    await _adapter.signOut();
    await _dao.clear();
    if (userId != null) _telemetry.logout(userId: userId);
    state = const AsyncData(AuthSession.signedOut());
  }

  Future<void> _onAdapterState(AuthAdapterState adapterState) async {
    final session = _sessionFromAdapter(adapterState);
    if (session is SignedOutSession) {
      await _dao.clear();
    } else {
      await _persistSession(adapterState, session);
    }
    state = AsyncData(session);
  }

  Future<void> _persistSession(
    AuthAdapterState adapterState,
    AuthSession session,
  ) async {
    final userId = adapterState.userId;
    if (userId == null) return;
    final displayName = session.displayName ?? '';
    await _dao.upsert(
      userId: userId,
      kind: _kindToString(adapterState.kind),
      displayName: displayName,
      avatarColor: _avatarColorFor(session),
      expiresAt: adapterState.expiresAt ??
          DateTime.now().toUtc().add(const Duration(hours: 1)),
      refreshAfter: adapterState.refreshAfter ??
          DateTime.now().toUtc().add(const Duration(minutes: 50)),
    );
  }

  AuthSession _sessionFromAdapter(AuthAdapterState s) {
    switch (s.kind) {
      case AuthAdapterKind.signedOut:
        return const AuthSession.signedOut();
      case AuthAdapterKind.anonymous:
        return AuthSession.anonymous(userId: s.userId!);
      case AuthAdapterKind.keypair:
        return AuthSession.keypair(
          userId: s.userId!,
          displayName: s.nickname ?? '',
        );
      case AuthAdapterKind.oauthGoogle:
        return AuthSession.oauth(
          userId: s.userId!,
          displayName: s.nickname ?? '',
          provider: AuthProvider.google,
        );
      case AuthAdapterKind.oauthApple:
        return AuthSession.oauth(
          userId: s.userId!,
          displayName: s.nickname ?? '',
          provider: AuthProvider.apple,
        );
    }
  }

  AuthSession _sessionFromCache(CachedAuthSessionData cached) {
    switch (cached.kind) {
      case 'oauth_google':
        return AuthSession.oauth(
          userId: cached.userId,
          displayName: cached.displayName,
          provider: AuthProvider.google,
          avatarColor: cached.avatarColor,
        );
      case 'oauth_apple':
        return AuthSession.oauth(
          userId: cached.userId,
          displayName: cached.displayName,
          provider: AuthProvider.apple,
          avatarColor: cached.avatarColor,
        );
      case 'keypair':
        return AuthSession.keypair(
          userId: cached.userId,
          displayName: cached.displayName,
          avatarColor: cached.avatarColor,
        );
      default:
        return const AuthSession.signedOut();
    }
  }

  String _kindToString(AuthAdapterKind kind) {
    switch (kind) {
      case AuthAdapterKind.oauthGoogle:
        return 'oauth_google';
      case AuthAdapterKind.oauthApple:
        return 'oauth_apple';
      case AuthAdapterKind.keypair:
        return 'keypair';
      case AuthAdapterKind.anonymous:
        return 'anonymous';
      case AuthAdapterKind.signedOut:
        return 'signed_out';
    }
  }

  String? _avatarColorFor(AuthSession session) {
    return session.maybeWhen(
      keypair: (_, _, color) => color,
      oauth: (_, _, _, color, _) => color,
      orElse: () => null,
    );
  }
}
