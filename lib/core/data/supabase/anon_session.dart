import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';

/// Ensures a Supabase session is in place before public-route widgets
/// mount. Public spectator screens (M4.2) need a valid JWT — even an
/// anonymous one — for RLS-gated reads and Realtime subscribes (per
/// ADR-0023). The bootstrapper covers the cold-start case where the
/// browser opens a /public URL without any cached session.
///
/// Boot path:
///   1. Read [SupabaseAuthAdapter.currentState] — Supabase's gotrue
///      client restores any persisted session (anonymous, keypair,
///      OAuth) during `Supabase.initialize` from its own secure-storage
///      backend, so the adapter snapshot already reflects what was
///      cached locally. No additional `flutter_secure_storage` read is
///      needed at this layer.
///   2. If [AuthAdapterKind.signedOut], call `signInAnonymously()`.
///      The fresh JWT is persisted by gotrue automatically.
///   3. Otherwise (anonymous / keypair / oauth already active) no-op.
///
/// Idempotent: concurrent callers share the same in-flight Future, and
/// repeat calls after success return immediately.
class AnonSessionBootstrapper {
  AnonSessionBootstrapper(this._adapter);

  final SupabaseAuthAdapter _adapter;

  /// In-flight or completed sign-in. Held so concurrent callers (e.g.
  /// a public-route deeplink that mounts two screens in the same frame)
  /// share a single network round-trip.
  Future<void>? _pending;

  /// Idempotent entry point. Returns once a usable session — anonymous
  /// or richer — is active on the adapter.
  Future<void> ensureAnonSession() {
    if (_adapter.currentState.isAuthenticated) {
      // Already keypair / OAuth — public reads work with the stronger
      // JWT and we leave it alone.
      return Future<void>.value();
    }
    if (_adapter.currentState.kind == AuthAdapterKind.anonymous) {
      // Cold-start with gotrue's persisted anon session still valid.
      return Future<void>.value();
    }
    return _pending ??= _signIn();
  }

  Future<void> _signIn() async {
    try {
      await _adapter.signInAnonymously();
    } catch (_) {
      // Clear the cache so a retry from the next public-route hit can
      // try again instead of returning the failed Future forever.
      _pending = null;
      rethrow;
    }
  }
}

/// Provider exposed to the router shell. Single instance per
/// ProviderContainer so the in-flight de-duplication holds across
/// callers.
final anonSessionBootstrapperProvider = Provider<AnonSessionBootstrapper>(
  (ref) => AnonSessionBootstrapper(ref.watch(supabaseAuthAdapterProvider)),
);
