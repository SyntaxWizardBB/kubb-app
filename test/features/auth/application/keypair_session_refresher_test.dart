import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/application/keypair_session_refresher.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';

/// Coverage for the Phase-1 keypair JWT auto-refresh (W2-T1 / R1-F-03).
///
/// ADR-0010 §"Auth challenge for keypair accounts" gives the keypair
/// access token a 1h lifetime with no refresh-token counterpart, so the
/// OAuth path's `autoRefreshToken` does nothing for keypair sessions.
/// The refresher must therefore re-sign a fresh challenge shortly
/// before each expiry on its own.
///
/// All time is driven through [FakeAsync] so the suite stays
/// deterministic and runs in milliseconds — a one-hour token elapses
/// virtually.
void main() {
  // Internal margin from KeypairSessionRefresher kept in sync with the
  // production constant. The tests treat it as the contract: re-sign
  // exactly `kKeypairRefreshMargin` before expiresAt.
  const margin = kKeypairRefreshMargin;

  /// Builds a fresh harness inside a [FakeAsync] zone. The closure-style
  /// API keeps every test's clock, stream, adapter, and counters
  /// scoped to one block — no late-init aliasing across tests.
  void withHarness(
    void Function(_Harness h, FakeAsync async) body, {
    Future<void> Function(_Harness h)? onReSign,
  }) {
    FakeAsync().run((async) {
      final start = DateTime.utc(2026, 5, 27, 12);
      final bridge = StreamController<AuthAdapterState>.broadcast();
      addTearDown(bridge.close);
      final harness = _Harness(
        bridge: bridge,
        start: start,
        async: async,
      );
      harness.refresher = KeypairSessionRefresher(
        adapter: _StubAdapter(bridge.stream),
        reSign: () async {
          harness.reSignCount += 1;
          final hook = onReSign;
          if (hook != null) await hook(harness);
        },
        now: harness.now,
      );
      try {
        body(harness, async);
      } finally {
        unawaited(harness.refresher.dispose());
        async.flushMicrotasks();
      }
    });
  }

  test('fires signInWithChallenge exactly margin before expiry', () {
    withHarness((h, async) {
      final expiresAt = h.start.add(const Duration(hours: 1));
      h.emitKeypair(expiresAt: expiresAt);
      async.flushMicrotasks();

      expect(h.refresher.isScheduled, isTrue);
      expect(h.refresher.scheduledFor, expiresAt.subtract(margin));

      // Just before the refresh point: nothing has fired yet.
      async.elapse(
          const Duration(hours: 1) - margin - const Duration(seconds: 1));
      expect(h.reSignCount, 0);

      // Cross the threshold — the timer fires.
      async
        ..elapse(const Duration(seconds: 1))
        ..flushMicrotasks();
      expect(h.reSignCount, 1);
    });
  });

  test(
    'acceptance: 30-second expiry triggers re-sign before the cliff '
    '(R1-F-03)',
    () {
      withHarness((h, async) {
        // expiresAt only 30s out → target = expiresAt - 5min sits in
        // the past, so the refresher must fire immediately. This is
        // the acceptance scenario from the brief.
        final expiresAt = h.start.add(const Duration(seconds: 30));
        h.emitKeypair(expiresAt: expiresAt);

        // Past-due target → fires on the next event-loop tick, well
        // before the 30-second cliff.
        async
          ..flushMicrotasks()
          ..elapse(const Duration(milliseconds: 1))
          ..flushMicrotasks();
        expect(h.reSignCount, 1);
        // And critically: it happened BEFORE expiresAt.
        expect(async.elapsed, lessThan(const Duration(seconds: 30)));
      });
    },
  );

  test('dispose cancels the pending timer — no re-sign after teardown', () {
    withHarness((h, async) {
      final expiresAt = h.start.add(const Duration(hours: 1));
      h.emitKeypair(expiresAt: expiresAt);
      async.flushMicrotasks();
      expect(h.refresher.isScheduled, isTrue);

      unawaited(h.refresher.dispose());
      async.flushMicrotasks();
      expect(h.refresher.isScheduled, isFalse);

      // Elapse well past the original target — nothing fires.
      async
        ..elapse(const Duration(hours: 2))
        ..flushMicrotasks();
      expect(h.reSignCount, 0);
    });
  });

  test('re-emission with identical expiresAt does NOT stack a second timer',
      () {
    withHarness((h, async) {
      final expiresAt = h.start.add(const Duration(hours: 1));
      h.emitKeypair(expiresAt: expiresAt);
      async.flushMicrotasks();
      final firstTarget = h.refresher.scheduledFor;

      // Adapter re-emits the same state (e.g. listener replay after
      // a recoverSession internal touch). The scheduled instant must
      // stay identical — and we must still only see ONE re-sign.
      h
        ..emitKeypair(expiresAt: expiresAt)
        ..emitKeypair(expiresAt: expiresAt);
      async.flushMicrotasks();
      expect(h.refresher.scheduledFor, firstTarget);

      async
        ..elapse(const Duration(hours: 1) - margin)
        ..flushMicrotasks();
      expect(h.reSignCount, 1, reason: 'exactly one re-sign per expiry');
    });
  });

  test('changed expiresAt cancels the old timer and arms a new one', () {
    withHarness((h, async) {
      final firstExpiry = h.start.add(const Duration(hours: 1));
      h.emitKeypair(expiresAt: firstExpiry);
      async.flushMicrotasks();
      expect(h.refresher.scheduledFor, firstExpiry.subtract(margin));

      // New session lands with a later expiry (typical post-refresh
      // emission after recoverSession). Pending timer for the old
      // expiry must be discarded; new target installed.
      final secondExpiry = h.start.add(const Duration(hours: 2));
      h.emitKeypair(expiresAt: secondExpiry);
      async.flushMicrotasks();
      expect(h.refresher.scheduledFor, secondExpiry.subtract(margin));

      // Elapse past the OLD target — must not fire (it was cancelled).
      async
        ..elapse(
            const Duration(hours: 1) - margin + const Duration(seconds: 5))
        ..flushMicrotasks();
      expect(h.reSignCount, 0, reason: 'cancelled timer must not fire');

      // Elapse to the NEW target.
      async
        ..elapse(const Duration(hours: 1))
        ..flushMicrotasks();
      expect(h.reSignCount, 1);
    });
  });

  test('non-keypair states cancel any pending refresh', () {
    withHarness((h, async) {
      final expiresAt = h.start.add(const Duration(hours: 1));
      h.emitKeypair(expiresAt: expiresAt);
      async.flushMicrotasks();
      expect(h.refresher.isScheduled, isTrue);

      // User signed out (or swapped to OAuth) — drop the timer.
      h.bridge.add(AuthAdapterState.signedOut);
      async.flushMicrotasks();
      expect(h.refresher.isScheduled, isFalse);

      async
        ..elapse(const Duration(hours: 2))
        ..flushMicrotasks();
      expect(h.reSignCount, 0);
    });
  });

  test('pause disarms the timer; nothing fires while backgrounded (C7-T1)', () {
    withHarness((h, async) {
      final expiresAt = h.start.add(const Duration(hours: 1));
      h.emitKeypair(expiresAt: expiresAt);
      async.flushMicrotasks();
      expect(h.refresher.isScheduled, isTrue);

      // App backgrounded → controller pauses the refresher.
      h.refresher.pause();
      expect(h.refresher.isScheduled, isFalse,
          reason: 'pause must disarm the one-shot timer');

      // Elapse past the original refresh point — no re-sign while paused.
      async
        ..elapse(const Duration(hours: 1))
        ..flushMicrotasks();
      expect(h.reSignCount, 0, reason: 'paused refresher must not fire');
    });
  });

  test('resume re-arms from the remembered target (C7-T1)', () {
    withHarness((h, async) {
      final expiresAt = h.start.add(const Duration(hours: 1));
      h.emitKeypair(expiresAt: expiresAt);
      async.flushMicrotasks();
      final target = h.refresher.scheduledFor;

      h.refresher.pause();
      expect(h.refresher.isScheduled, isFalse);

      // App foregrounded → controller resumes the refresher (after re-sign).
      h.refresher.resume();
      expect(h.refresher.isScheduled, isTrue,
          reason: 'resume must re-arm the one-shot timer');
      expect(h.refresher.scheduledFor, target,
          reason: 'resume restores the pre-pause target');

      // The re-armed timer still fires at the original refresh point.
      async
        ..elapse(const Duration(hours: 1) - margin)
        ..flushMicrotasks();
      expect(h.reSignCount, 1);
    });
  });

  test('resume fires immediately when the target elapsed while paused (C7-T1)',
      () {
    withHarness((h, async) {
      final expiresAt = h.start.add(const Duration(hours: 1));
      h.emitKeypair(expiresAt: expiresAt);
      async.flushMicrotasks();

      h.refresher.pause();
      // Token's refresh point passes while the app sits in the background.
      async.elapse(const Duration(hours: 1));

      h.refresher.resume();
      async
        ..flushMicrotasks()
        ..elapse(const Duration(milliseconds: 1))
        ..flushMicrotasks();
      expect(h.reSignCount, 1,
          reason: 'an already-due refresh re-mints right after resume');
    });
  });

  test('re-sign failure does not throw out of the timer callback', () {
    // A thrown error inside the timer callback would surface as an
    // uncaught async error and FakeAsync.run would forward it out of
    // the block. Reaching the assertion below is the proof of "no
    // rethrow".
    withHarness(
      onReSign: (_) async => throw StateError('challenge server down'),
      (h, async) {
        final expiresAt = h.start.add(const Duration(hours: 1));
        h.emitKeypair(expiresAt: expiresAt);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(hours: 1) - margin)
          ..flushMicrotasks();
        expect(h.reSignCount, 1);
      },
    );
  });
}

/// Per-test bundle of mutable state: clock anchor, broadcast bridge,
/// FakeAsync handle, the refresher under test, and a re-sign counter.
class _Harness {
  _Harness({
    required this.bridge,
    required this.start,
    required this.async,
  });

  final StreamController<AuthAdapterState> bridge;
  final DateTime start;
  final FakeAsync async;

  late final KeypairSessionRefresher refresher;
  int reSignCount = 0;

  DateTime now() =>
      start.add(Duration(microseconds: async.elapsed.inMicroseconds));

  /// Emits a keypair session directly through the bridge — bypasses
  /// the fake adapter's attachKeypair plumbing so tests own the
  /// expiresAt value bit-for-bit.
  void emitKeypair({
    required DateTime expiresAt,
    String userId = 'u1',
    String nickname = 'tester',
  }) {
    bridge.add(AuthAdapterState(
      userId: userId,
      kind: AuthAdapterKind.keypair,
      expiresAt: expiresAt,
      refreshAfter: expiresAt.subtract(const Duration(minutes: 5)),
      nickname: nickname,
    ));
  }
}

/// Minimal [SupabaseAuthAdapter] that only implements the stream the
/// refresher consumes. Every other method throws — the refresher is
/// not allowed to call them.
class _StubAdapter implements SupabaseAuthAdapter {
  _StubAdapter(this._stream);
  final Stream<AuthAdapterState> _stream;

  @override
  Stream<AuthAdapterState> get onAuthStateChange => _stream;

  @override
  AuthAdapterState get currentState =>
      throw UnimplementedError('not used by refresher');

  @override
  String? get wireAccessToken =>
      throw UnimplementedError('not used by refresher');

  @override
  Future<AuthAdapterState> refreshSession() =>
      throw UnimplementedError('not used by refresher');

  @override
  Future<void> signInWithOAuth(AuthOAuthProvider provider) =>
      throw UnimplementedError('not used by refresher');

  @override
  Future<AuthAdapterState> signInAnonymously() =>
      throw UnimplementedError('not used by refresher');

  @override
  Future<AuthAdapterState> attachKeypair({
    required String nickname,
    required List<int> publicKey,
    required String earlyAccessCode,
    String? avatarColor,
  }) =>
      throw UnimplementedError('not used by refresher');

  @override
  Future<Uint8List> requestKeypairChallenge(List<int> publicKey) =>
      throw UnimplementedError('not used by refresher');

  @override
  Future<AuthVerifyResult> verifyKeypairSignature({
    required List<int> publicKey,
    required List<int> challenge,
    required List<int> signature,
  }) =>
      throw UnimplementedError('not used by refresher');

  @override
  Future<AuthAdapterState> linkOAuthToCurrentUser(AuthOAuthProvider provider) =>
      throw UnimplementedError('not used by refresher');

  @override
  Future<OAuthCallbackResult> exchangeOAuthCallback(Uri uri) =>
      throw UnimplementedError('not used by refresher');

  @override
  Future<void> completeOAuthSignIn(Uri uri) =>
      throw UnimplementedError('not used by refresher');

  @override
  Future<AuthAdapterState> reconcileOAuthForKeypairUser({
    required AuthOAuthProvider provider,
    required List<int> publicKey,
    required List<int> challenge,
    required List<int> signature,
    required String oauthAccessToken,
  }) =>
      throw UnimplementedError('not used by refresher');

  @override
  Future<void> deleteCurrentAccount() =>
      throw UnimplementedError('not used by refresher');

  @override
  Future<void> signOut() =>
      throw UnimplementedError('not used by refresher');
}
