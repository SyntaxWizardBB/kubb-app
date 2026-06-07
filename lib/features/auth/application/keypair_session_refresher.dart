import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/keypair_signing_service.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';
import 'package:logging/logging.dart';

final _log = Logger('auth.keypair_refresh');

/// Re-mint window before the JWT actually expires. Keeps a comfortable
/// buffer so a re-sign that takes a few seconds (challenge round-trip
/// plus signature) still beats the cliff.
const Duration kKeypairRefreshMargin = Duration(minutes: 5);

/// Schedules a re-sign of the keypair JWT shortly before it expires.
///
/// ADR-0010 §"Auth challenge for keypair accounts" gives the Phase-1
/// keypair JWT a 1h lifetime with no refresh token. Without an active
/// timer the session goes silently stale: the in-memory gotrue session
/// keeps reporting the access token, every authenticated RPC gets a 401,
/// and the user only learns about it on the next write attempt. The
/// OAuth path is covered by gotrue's own `autoRefreshToken`; this class
/// is the keypair equivalent.
///
/// Strategy:
///   * Listen to [SupabaseAuthAdapter.onAuthStateChange].
///   * Whenever a keypair session with an `expiresAt` arrives, schedule
///     a one-shot [Timer] for `expiresAt - margin`.
///   * Cancel any previously-scheduled timer first so a stream of
///     emissions with shifting expiry never doubles up.
///   * When the timer fires, run [KeypairSigningService.signInWithChallenge].
///     The verify step calls `recoverSession`, which re-emits a fresh
///     state on the same auth-state stream — our own listener then
///     schedules the next refresh from that new expiresAt.
///
/// Failure handling is best-effort: a failed re-sign logs and leaves
/// the stale session as-is. The next authenticated RPC will surface
/// the auth error via the normal channel; users can retry via the UI.
class KeypairSessionRefresher {
  KeypairSessionRefresher({
    required SupabaseAuthAdapter adapter,
    required Future<void> Function() reSign,
    DateTime Function() now = _systemNow,
  })  : _adapter = adapter,
        _reSign = reSign,
        _now = now {
    _sub = _adapter.onAuthStateChange.listen(_onState);
  }

  final SupabaseAuthAdapter _adapter;
  final Future<void> Function() _reSign;
  final DateTime Function() _now;

  StreamSubscription<AuthAdapterState>? _sub;
  Timer? _timer;
  DateTime? _scheduledFor;
  bool _disposed = false;

  /// True while the refresher is paused (app backgrounded). While paused the
  /// one-shot timer is held cancelled and no new timer is armed from incoming
  /// auth-state emissions; [resume] re-arms from the remembered target.
  bool _paused = false;

  static DateTime _systemNow() => DateTime.now().toUtc();

  /// Exposed for tests so they can assert the timer is armed for the
  /// expected wall-clock instant without poking at the private field.
  DateTime? get scheduledFor => _scheduledFor;

  /// True while a refresh timer is armed.
  bool get isScheduled => _timer != null;

  void _onState(AuthAdapterState state) {
    if (_disposed) return;
    if (state.kind != AuthAdapterKind.keypair) {
      // Adapter moved away from keypair (signed-out, swapped to OAuth,
      // anonymous downgrade). Drop the pending timer; if a keypair
      // session lands later we'll re-schedule from its emission.
      _cancelTimer();
      return;
    }
    final expiresAt = state.expiresAt;
    if (expiresAt == null) {
      _cancelTimer();
      return;
    }
    // Idempotency: a re-emission of the same state (e.g. a touch from
    // recoverSession after our own re-sign) must not stack a second
    // timer. We treat the scheduled wall-clock instant as the key —
    // two emissions with the same expiresAt are the same job.
    final target = expiresAt.subtract(kKeypairRefreshMargin);
    if (_paused) {
      // Backgrounded: remember WHEN to fire but keep the timer disarmed.
      // resume() re-arms from this remembered target after the foreground
      // re-sign, so a session expiring in the background is re-minted as
      // soon as the app returns.
      _scheduledFor = target;
      return;
    }
    if (_timer != null && _scheduledFor == target) {
      return;
    }
    _cancelTimer();
    final delay = target.difference(_now());
    if (delay <= Duration.zero) {
      // Already past the refresh point — fire immediately. Async-gap
      // through Timer.run so we don't reenter onAuthStateChange
      // synchronously from inside its own listener.
      _scheduledFor = target;
      _timer = Timer(Duration.zero, _fire);
      return;
    }
    _scheduledFor = target;
    _timer = Timer(delay, _fire);
    _log.fine(
      'keypair refresh scheduled in ${delay.inSeconds}s '
      '(expiresAt=$expiresAt)',
    );
  }

  Future<void> _fire() async {
    _timer = null;
    _scheduledFor = null;
    if (_disposed) return;
    try {
      _log.info('keypair refresh firing — re-signing with stored privkey');
      await _reSign();
    } on Object catch (e, st) {
      // Failure does not bubble: the session simply stays stale until
      // the user triggers another action. Logging gives us a trail.
      _log.warning('keypair refresh failed', e, st);
    }
  }

  /// Pauses the refresher while the app is backgrounded (battery regime,
  /// ADR-0029 §C7-T1). The pending one-shot timer is cancelled so no
  /// re-sign fires in the background, but the remembered [scheduledFor]
  /// target is preserved so [resume] can re-arm it. No [Timer.periodic]
  /// is involved — this is the same one-shot timer, simply held disarmed.
  void pause() {
    if (_disposed || _paused) return;
    _paused = true;
    // Drop the live timer but keep _scheduledFor so resume can re-arm.
    final target = _scheduledFor;
    _timer?.cancel();
    _timer = null;
    _scheduledFor = target;
  }

  /// Resumes the refresher on foreground after the lifecycle controller has
  /// already re-signed the wire session. Re-arms the one-shot timer from the
  /// target remembered at [pause]: if that instant has already passed it
  /// fires immediately, otherwise it is scheduled for the remaining delay.
  void resume() {
    if (_disposed || !_paused) return;
    _paused = false;
    final target = _scheduledFor;
    if (target == null) {
      // Nothing was scheduled before the pause (no keypair session). The
      // next auth-state emission will arm the timer normally.
      return;
    }
    final delay = target.difference(_now());
    _timer?.cancel();
    _timer = Timer(delay <= Duration.zero ? Duration.zero : delay, _fire);
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _scheduledFor = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    _cancelTimer();
    await _sub?.cancel();
    _sub = null;
  }
}

/// Wires up [KeypairSessionRefresher] against the live adapter and the
/// keypair signing service. The provider is read once at bootstrap so
/// the listener stays attached for the whole app lifetime; tear-down
/// happens through `ref.onDispose` when the container itself goes away.
final keypairSessionRefresherProvider =
    Provider<KeypairSessionRefresher>((ref) {
  final adapter = ref.read(supabaseAuthAdapterProvider);
  final signing = ref.read(keypairSigningServiceProvider);
  final refresher = KeypairSessionRefresher(
    adapter: adapter,
    reSign: signing.signInWithChallenge,
  );
  ref.onDispose(() {
    // Fire-and-forget: the container is going away regardless.
    unawaited(refresher.dispose());
  });
  return refresher;
});
