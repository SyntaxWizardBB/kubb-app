import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/application/keypair_signing_service.dart';
import 'package:kubb_app/features/auth/data/auth_telemetry.dart';
import 'package:kubb_app/features/auth/data/dao/cached_auth_session_dao.dart';
import 'package:kubb_app/features/auth/data/keypair_storage.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter_impl.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _wireSessionLog = Logger('auth.bootstrap');

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

/// Outcome of [ensureWireSession]. Surfaced so call-sites can branch
/// (and tests can assert) without parsing log lines.
enum WireSessionOutcome {
  /// Wire token already present — no work was needed.
  alreadyLive,

  /// Keypair session detected and `signInWithChallenge` succeeded.
  keypairResigned,

  /// OAuth session detected and `refreshSession` succeeded.
  oauthRefreshed,

  /// No cached session — bootstrap will end up signed-out, no re-sign
  /// possible. Not an error.
  noCachedSession,

  /// Cache shows a session the helper cannot recover (anonymous, or
  /// keypair without a private key still in secure storage). The
  /// caller decides whether to drop the cache or surface the issue.
  unrecoverable,

  /// Recovery was attempted but failed (network, server reject). The
  /// drift cache stays as-is so a retry on the next bootstrap can try
  /// again; routing logic should treat the user as effectively
  /// signed-out for authenticated work.
  failed,
}

/// Pre-flight guard: ensures the underlying Supabase wire session is
/// live before any authenticated RPC fires. Resolves the cache-hydration
/// race documented as R1-F-02 (Mängel #9, `authentication required` on
/// tournament create): the drift cache may hold a keypair/OAuth session
/// while `supabase.auth.currentSession` is empty, e.g. after a cold
/// start, an OAuth refresh-token rotation, or a Phase-1 keypair access
/// token expiry.
///
/// Strategy:
///   - Keypair → run [KeypairSigningService.signInWithChallenge] which
///     re-derives the public key, requests a fresh challenge, signs it,
///     and lets the adapter hydrate the gotrue session via
///     `recoverSession`.
///   - OAuth → call [SupabaseAuthAdapter.refreshSession], which goes
///     through gotrue's standard refresh-token rotation.
///   - Anonymous → nothing to re-sign (anonymous sessions are minted
///     once per device install); reported as `unrecoverable`.
///
/// The helper is exported via [ensureWireSessionProvider] but is *not*
/// wired into every RPC call-site — that backlog lands in W2-T1.
/// Bootstrap calls it once after the drift cache is read; future
/// per-RPC guards can layer on top.
Future<WireSessionOutcome> ensureWireSession(Ref ref) async {
  final adapter = ref.read(supabaseAuthAdapterProvider);
  if (adapter.wireAccessToken != null) {
    return WireSessionOutcome.alreadyLive;
  }

  final cached = await ref.read(cachedAuthSessionDaoProvider).current();
  if (cached == null) {
    return WireSessionOutcome.noCachedSession;
  }

  switch (cached.kind) {
    case 'keypair':
      final keypair = ref.read(keypairStorageProvider);
      final privateKey = await keypair.load();
      if (privateKey == null) {
        _wireSessionLog.warning(
          'wire re-sign skipped: keypair cached but private key missing',
        );
        return WireSessionOutcome.unrecoverable;
      }
      try {
        _wireSessionLog.info(
          'wire re-sign triggered: keypair cache without live wire token',
        );
        await ref.read(keypairSigningServiceProvider).signInWithChallenge();
        return WireSessionOutcome.keypairResigned;
      } on Object catch (e, st) {
        _wireSessionLog.warning('wire re-sign failed (keypair)', e, st);
        return WireSessionOutcome.failed;
      }
    case 'oauth_google':
    case 'oauth_apple':
      try {
        _wireSessionLog.info(
          'wire re-sign triggered: oauth cache without live wire token',
        );
        await adapter.refreshSession();
        return WireSessionOutcome.oauthRefreshed;
      } on Object catch (e, st) {
        _wireSessionLog.warning('wire re-sign failed (oauth)', e, st);
        return WireSessionOutcome.failed;
      }
    case 'anonymous':
      // Anonymous sessions cannot be re-minted without losing the
      // user_id, which would orphan local data. Treat as a no-op and
      // let the caller decide (today: nothing).
      return WireSessionOutcome.unrecoverable;
    default:
      return WireSessionOutcome.unrecoverable;
  }
}

/// Riverpod handle on [ensureWireSession] so consumers can read it
/// without dragging a `Ref` around manually. Tests override
/// `supabaseAuthAdapterProvider` / `keypairSigningServiceProvider` to
/// drive the branches.
final ensureWireSessionProvider =
    Provider<Future<WireSessionOutcome> Function()>((ref) {
  return () => ensureWireSession(ref);
});

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

  /// Monotonic counter bumped on every imperative state change
  /// (sign-out today; future explicit sign-in promotions when they
  /// come). Adapter events captured before the bump are ignored,
  /// which kills the race a fast sign-in→sign-out→sign-in produces:
  /// without it, a delayed AuthState event from the first sign-in can
  /// land after the second sign-out and overwrite SignedOut with a
  /// stale authenticated session in drift.
  int _generation = 0;

  SupabaseAuthAdapter get _adapter =>
      ref.read(supabaseAuthAdapterProvider);
  CachedAuthSessionDao get _dao =>
      ref.read(cachedAuthSessionDaoProvider);
  KeypairStorage get _keypairStorage =>
      ref.read(keypairStorageProvider);
  AuthTelemetry get _telemetry => ref.read(authTelemetryProvider);

  @override
  Future<AuthSession> build() async {
    ref.onDispose(() => _sub?.cancel());

    // Resolve initial state from cache BEFORE subscribing so the
    // adapter's first snapshot (which lands as a microtask after
    // _subscribe) cannot race with this lookup. After a cold start
    // the snapshot is the bare anonymous Supabase session, even when
    // the cache holds a richer keypair session — the order matters.
    final cached = await _dao.current();
    final AuthSession initial;
    if (cached != null) {
      initial = _sessionFromCache(cached);
    } else {
      final adapterState = _adapter.currentState;
      initial = adapterState.isAuthenticated
          ? _sessionFromAdapter(adapterState)
          : const AuthSession.signedOut();
    }
    _subscribe();
    return initial;
  }

  void _subscribe() {
    final subscribedGeneration = _generation;
    // Drop the first emission — the adapter's `onAuthStateChange`
    // stream yields a snapshot of `_state` on subscription. After a
    // cold start that snapshot is the bare anonymous Supabase session
    // even when the local cache holds a richer keypair session, and
    // letting it through would clobber the cache. We already read
    // `_adapter.currentState` synchronously in `build()` for the
    // no-cache path.
    _sub = _adapter.onAuthStateChange.skip(1).listen((adapterState) {
      // Stream.listen takes a synchronous callback; the handler is
      // async by nature so we deliberately discard the returned
      // Future. Each subscription is bound to the generation in
      // effect at the moment of `listen()`. signOut bumps the
      // generation and re-subscribes, so any event that was already
      // in flight on the previous subscription tags an older
      // generation and gets dropped.
      unawaited(_onAdapterState(adapterState, subscribedGeneration));
    });
  }

  Future<void> signOut() async {
    final userId = state.value?.userId;
    // Tear down the live subscription first: any event already
    // emitted by the adapter but not yet delivered to our listener
    // belongs to the pre-signOut session and must not influence our
    // state. Bumping _generation invalidates any handler that did
    // start before the cancel completed.
    _generation++;
    await _sub?.cancel();
    _sub = null;
    await _adapter.signOut();
    await _dao.clear();
    await _keypairStorage.clear();
    if (userId != null) _telemetry.logout(userId: userId);
    state = const AsyncData(AuthSession.signedOut());
    _subscribe();
  }

  /// Reflects a successful cloud-profile mutation back into the cached
  /// session so the display-profile provider (and every UI surface
  /// derived from it) sees the new nickname/avatar without waiting for
  /// the next adapter emission. The DAO row is upserted in lock-step with the
  /// in-memory state to keep the two sources of truth aligned across a
  /// cold restart. No-op when the session is signed-out/anonymous —
  /// those flows have no cloud profile to mirror.
  Future<void> updateCachedProfile({
    required String displayName,
    String? avatarColor,
  }) async {
    final current = state.value;
    if (current is! KeypairSession && current is! OAuthSession) return;
    final AuthSession next;
    final String kind;
    if (current is KeypairSession) {
      next = AuthSession.keypair(
        userId: current.userId,
        displayName: displayName,
        avatarColor: avatarColor,
      );
      kind = 'keypair';
    } else if (current is OAuthSession) {
      next = AuthSession.oauth(
        userId: current.userId,
        displayName: displayName,
        provider: current.provider,
        avatarColor: avatarColor,
        hasKeypairFallback: current.hasKeypairFallback,
      );
      kind = current.provider == AuthProvider.google
          ? 'oauth_google'
          : 'oauth_apple';
    } else {
      return;
    }
    final userId = next.userId;
    if (userId == null) return;
    // Preserve the existing token deadlines — only the display fields
    // change. Fall back to the conservative one-hour horizon used
    // elsewhere when the row is absent (e.g. test containers).
    final existing = await _dao.current();
    final now = DateTime.now().toUtc();
    await _dao.upsert(
      userId: userId,
      kind: existing?.kind ?? kind,
      displayName: displayName,
      avatarColor: avatarColor,
      expiresAt: existing?.expiresAt ?? now.add(const Duration(hours: 1)),
      refreshAfter:
          existing?.refreshAfter ?? now.add(const Duration(minutes: 50)),
    );
    state = AsyncData(next);
  }

  Future<void> _onAdapterState(
    AuthAdapterState adapterState,
    int eventGeneration,
  ) async {
    if (eventGeneration != _generation) {
      return;
    }
    final incoming = _sessionFromAdapter(adapterState);
    // Don't let a bare `anonymous` adapter snapshot clobber a richer
    // session we already restored from the local cache. After a cold
    // start the underlying Supabase session is still the anonymous one
    // GoTrue minted at signup; the adapter cannot know on its own that
    // a keypair credential was attached. The drift cache does, so we
    // trust it for same-user emissions.
    final current = state.value;
    final isAnonymousDowngrade = incoming is AnonymousSession &&
        current is KeypairSession &&
        current.userId == incoming.userId;
    if (isAnonymousDowngrade) {
      return;
    }
    if (incoming is SignedOutSession) {
      await _dao.clear();
    } else {
      await _persistSession(adapterState, incoming);
    }
    if (eventGeneration != _generation) {
      return;
    }
    state = AsyncData(incoming);
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
      case 'anonymous':
        return AuthSession.anonymous(userId: cached.userId);
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
