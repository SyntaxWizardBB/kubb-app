import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';
import 'package:logging/logging.dart';

part 'account_upgrade_controller.freezed.dart';

final _log = Logger('auth.upgrade');

/// Tracks whether an OAuth upgrade is mid-flight, so the auth controller
/// can gate the transient forked-OAuth emission out of the drift cache
/// (ADR-0042 §Clobber-Fenster). `null` when idle; otherwise the keypair
/// user_id whose identity must survive until reconcile re-mints.
class UpgradeInFlight {
  const UpgradeInFlight({required this.keypairUserId});

  final String keypairUserId;
}

class UpgradeInFlightNotifier extends Notifier<UpgradeInFlight?> {
  @override
  UpgradeInFlight? build() => null;

  // Named verb, not a setter, so the call site reads as an action.
  // ignore: use_setters_to_change_properties
  void mark(UpgradeInFlight value) => state = value;
  void clear() => state = null;
}

final upgradeInFlightProvider =
    NotifierProvider<UpgradeInFlightNotifier, UpgradeInFlight?>(
        UpgradeInFlightNotifier.new);

@freezed
class AccountUpgradeState with _$AccountUpgradeState {
  const factory AccountUpgradeState.idle() = _UpgradeIdle;
  const factory AccountUpgradeState.launching(AuthProvider provider) =
      _UpgradeLaunching;
  const factory AccountUpgradeState.awaitingCallback(AuthProvider provider) =
      _UpgradeAwaitingCallback;
  const factory AccountUpgradeState.reconciling(AuthProvider provider) =
      _UpgradeReconciling;
  const factory AccountUpgradeState.done() = _UpgradeDone;
  const factory AccountUpgradeState.failed({
    required String code,
    AuthProvider? provider,
  }) = _UpgradeFailed;
}

/// Window after launch within which the deep-link callback must arrive.
/// Past it, the user almost certainly abandoned the browser. Exposed as
/// a provider so tests can shrink it instead of waiting three minutes.
final upgradeCallbackTimeoutProvider =
    Provider<Duration>((ref) => const Duration(minutes: 3));

final accountUpgradeControllerProvider =
    NotifierProvider<AccountUpgradeController, AccountUpgradeState>(
        AccountUpgradeController.new);

class AccountUpgradeController extends Notifier<AccountUpgradeState> {
  Timer? _timeout;
  List<int>? _seed;
  String? _keypairUserId;

  @override
  AccountUpgradeState build() {
    ref.onDispose(() => _timeout?.cancel());
    return const AccountUpgradeState.idle();
  }

  bool get _inFlight => state.maybeWhen(
        awaitingCallback: (_) => true,
        reconciling: (_) => true,
        orElse: () => false,
      );

  Future<void> linkOAuth(AuthProvider provider) async {
    final session = ref.read(authControllerProvider).value;
    final canLink = session is KeypairSession ||
        (session is OAuthSession && session.hasKeypairFallback);
    final userId = session?.userId;
    if (!canLink || userId == null) {
      state = AccountUpgradeState.failed(code: 'not_keypair', provider: provider);
      return;
    }

    // Seed must be on the device before the browser opens. Missing seed
    // means we could never produce Proof A, so fail loud and DO NOT
    // start the OAuth flow (ADR-0042 §Flow A precondition).
    final seed = await ref.read(keypairStorageProvider).load();
    if (seed == null) {
      state = AccountUpgradeState.failed(
        code: 'keypair_seed_missing',
        provider: provider,
      );
      return;
    }
    _seed = seed;
    _keypairUserId = userId;

    state = AccountUpgradeState.launching(provider);
    final adapter = ref.read(supabaseAuthAdapterProvider);
    try {
      await adapter.linkOAuthToCurrentUser(_mapProvider(provider));
    } on Object {
      _clearFlight();
      state = AccountUpgradeState.failed(code: 'oauth_launch_failed',
          provider: provider);
      return;
    }

    // Arm the clobber gate before we go to awaitingCallback: the forked
    // OAuth session can land any time after the browser returns.
    ref
        .read(upgradeInFlightProvider.notifier)
        .mark(UpgradeInFlight(keypairUserId: userId));
    state = AccountUpgradeState.awaitingCallback(provider);
    _timeout?.cancel();
    _timeout = Timer(ref.read(upgradeCallbackTimeoutProvider), () {
      if (_inFlight) {
        _clearFlight();
        state = AccountUpgradeState.failed(
          code: 'callback_timeout',
          provider: provider,
        );
      }
    });
  }

  Future<void> completeLink(Uri uri) async {
    // The provider is still on the live state during the normal flow. After
    // a timeout the state is failed(callback_timeout, provider) — recover it
    // from there so a late callback can still finish the link.
    final provider = state.maybeWhen(
      awaitingCallback: (p) => p,
      reconciling: (p) => p,
      failed: (code, p) => code == 'callback_timeout' ? p : null,
      orElse: () => null,
    );
    if (provider == null) return;

    // Seed and keypair user_id normally survive in the notifier, but the
    // timeout path nulled them via _clearFlight. Re-hydrate from the active
    // keypair session + secure storage so a post-timeout callback recovers
    // the link instead of dropping it (ADR-0042 §Clobber-Fenster). If the
    // active session is no longer a keypair identity, or the seed is gone,
    // we bail — the forked session is never installed and the keypair
    // user_id stays intact.
    final keypairUserId = _keypairUserId ?? _activeKeypairUserId();
    final seed = _seed ?? await ref.read(keypairStorageProvider).load();
    if (seed == null || keypairUserId == null) return;

    // Re-arm the clobber gate before exchanging the callback. The deep
    // link can land via the post-timeout recovery path where the flag was
    // already cleared; exchangeOAuthCallback runs getSessionFromUrl, which
    // emits the forked OAuth session, and only an armed gate keeps that
    // user_id out of the drift cache (ADR-0042 §Clobber-Fenster). Marking
    // is idempotent — the normal in-flight path set the same value.
    _timeout?.cancel();
    ref
        .read(upgradeInFlightProvider.notifier)
        .mark(UpgradeInFlight(keypairUserId: keypairUserId));
    state = AccountUpgradeState.reconciling(provider);

    final adapter = ref.read(supabaseAuthAdapterProvider);
    final crypto = ref.read(cryptoServiceProvider);
    final telemetry = ref.read(authTelemetryProvider);

    // Pre-reconcile and reconcile errors map to failed(code): nothing was
    // committed server-side yet. The reconcile call is the commit point —
    // once it returns, the credential is written, the forked user deleted,
    // and the keypair token re-minted onto the keypair user_id.
    try {
      final callback = await adapter.exchangeOAuthCallback(uri);

      final publicKey = await crypto.publicKeyFromSeed(seed);
      final challenge = await adapter.requestKeypairChallenge(publicKey);
      final signature = await crypto.signEd25519(
        privateKey: seed,
        message: challenge,
      );

      await adapter.reconcileOAuthForKeypairUser(
        provider: _mapProvider(provider),
        publicKey: publicKey,
        challenge: challenge,
        signature: signature,
        oauthAccessToken: callback.accessToken,
      );
    } on ReconcileException catch (e) {
      _clearFlight();
      state = AccountUpgradeState.failed(code: e.code, provider: provider);
      return;
    } on Object {
      _clearFlight();
      state = AccountUpgradeState.failed(
        code: 'reconcile_failed',
        provider: provider,
      );
      return;
    }

    // Post-reconcile: the link is committed and the keypair user_id is
    // preserved. A failure here (DAO write, telemetry) must NOT downgrade
    // the outcome to failed — that would show a misleading error banner on
    // a link the server already accepted. Log it and end in done.
    try {
      // user_id is unchanged — the reconcile re-minted onto the keypair
      // user, so we push an OAuthSession with the SAME id and the
      // keypair retained as fallback.
      await ref.read(authControllerProvider.notifier).applyOAuthUpgrade(
            userId: keypairUserId,
            provider: provider,
          );
      telemetry.accountUpgrade(
        userId: keypairUserId,
        toKind: provider == AuthProvider.google ? 'oauth_google' : 'oauth_apple',
      );
    } on Object catch (e, st) {
      _log.warning('post-reconcile step failed after committed link', e, st);
    }

    _clearFlight();
    state = const AccountUpgradeState.done();
  }

  /// The active user_id only when the live session is still a keypair
  /// identity. Used by the post-timeout recovery in [completeLink] so a
  /// late callback can never reconcile against a non-keypair session.
  String? _activeKeypairUserId() {
    final session = ref.read(authControllerProvider).value;
    final isKeypair = session is KeypairSession ||
        (session is OAuthSession && session.hasKeypairFallback);
    return isKeypair ? session?.userId : null;
  }

  void _clearFlight() {
    _timeout?.cancel();
    _timeout = null;
    _seed = null;
    _keypairUserId = null;
    ref.read(upgradeInFlightProvider.notifier).clear();
  }

  AuthOAuthProvider _mapProvider(AuthProvider p) => p == AuthProvider.google
      ? AuthOAuthProvider.google
      : AuthOAuthProvider.apple;
}
