import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _log = Logger('push');

/// Owns the device's FCM-token lifecycle for the duration of a real
/// (keypair/OAuth) session: register on login + on token refresh,
/// unregister on sign-out.
///
/// ADR-0029 §6 / SPEC push-notifications §P3: push is the ONLY background
/// wake. Foreground messages are deliberately NOT shown as system
/// notifications — the live CDC/inbox subscription already drives the UI.
/// Background/terminated delivery is rendered by the OS from the FCM
/// `notification` block; the catch-up runs on the next app resume.
///
/// Kept alive for the app's lifetime by a single `ref.watch` in `app.dart`.
final pushNotificationsProvider = Provider<PushNotifications>((ref) {
  final push = PushNotifications(ref);
  ref.onDispose(push.dispose);
  push.start();
  return push;
});

class PushNotifications {
  PushNotifications(this._ref);

  final Ref _ref;

  ProviderSubscription<AsyncValue<AuthSession>>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  String? _registeredToken;
  String? _currentUserId;
  bool _messagingWired = false;

  SupabaseClient get _client => Supabase.instance.client;

  // Android today; iOS is prepared but its native wiring lands later.
  String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  void start() {
    _authSub = _ref.listen<AsyncValue<AuthSession>>(
      authControllerProvider,
      (_, next) => unawaited(_onAuth(next.value)),
      fireImmediately: true,
    );
  }

  Future<void> _onAuth(AuthSession? session) async {
    // Only real accounts get a push registration. Anonymous/signed-out
    // sessions never prompt for notifications.
    final isRealAccount = session is KeypairSession || session is OAuthSession;
    final userId = isRealAccount ? session?.userId : null;

    if (userId != null) {
      if (userId == _currentUserId) return; // already registered for this user
      _currentUserId = userId;
      await _registerForCurrentDevice();
    } else {
      await _unregisterCurrentDevice();
      _currentUserId = null;
    }
  }

  Future<void> _registerForCurrentDevice() async {
    try {
      _wireMessagingListeners();
      final messaging = FirebaseMessaging.instance;
      // Android 13+ POST_NOTIFICATIONS runtime prompt; no-op on older OS.
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token == null) {
        _log.info('push: no FCM token (no Play Services?) — skipping register');
        return;
      }
      await _registerToken(token);
    } on Object catch (e, st) {
      _log.warning('push: register failed', e, st);
    }
  }

  void _wireMessagingListeners() {
    if (_messagingWired) return;
    _messagingWired = true;
    final messaging = FirebaseMessaging.instance;
    _tokenRefreshSub = messaging.onTokenRefresh.listen(
      (t) => unawaited(_registerToken(t)),
    );
    // Tap on a background notification: the OS brings the app to the
    // foreground and the ADR-0029 resume path reconnects CDC + refreshes.
    // Kept as a seam for future deep-link routing on `message.data`.
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((_) {});
  }

  Future<void> _registerToken(String token) async {
    final userId = _currentUserId;
    if (userId == null) return;
    try {
      await _client.rpc<void>(
        'push_register_device_token',
        params: {'p_platform': _platform, 'p_token': token},
      );
      _registeredToken = token;
      _log.info('push: token registered ($_platform)');
    } on Object catch (e, st) {
      _log.warning('push: register RPC failed', e, st);
    }
  }

  Future<void> _unregisterCurrentDevice() async {
    final token = _registeredToken;
    if (token == null) return;
    try {
      await _client.rpc<void>(
        'push_unregister_device_token',
        params: {'p_token': token},
      );
    } on Object catch (e, st) {
      _log.warning('push: unregister RPC failed', e, st);
    } finally {
      _registeredToken = null;
    }
  }

  void dispose() {
    _authSub?.close();
    unawaited(_tokenRefreshSub?.cancel());
    unawaited(_openedSub?.cancel());
  }
}
