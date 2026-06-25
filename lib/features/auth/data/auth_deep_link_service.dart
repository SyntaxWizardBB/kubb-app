import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/account_upgrade_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/data/auth_redirect.dart';
import 'package:logging/logging.dart';

final _log = Logger('auth.deeplink');

/// Routes incoming `kubbapp://auth/callback` deep links.
///
/// Two entry points: the warm `uriLinkStream` and the cold-start
/// `getInitialLink()` (the app was launched by the callback itself).
/// For an upgrade callback (an OAuth upgrade is mid-flight) the URI goes
/// to [AccountUpgradeController.completeLink]; otherwise it is a
/// cold-start sign-in and goes to the adapter's `getSessionFromUrl`
/// path. The in-flight upgrade is checked FIRST so an upgrade callback
/// is never mistaken for a forked sign-in (ADR-0042 §Deep-Link).
class AuthDeepLinkService {
  AuthDeepLinkService(this._ref, {AppLinks? appLinks})
      : _appLinks = appLinks ?? AppLinks();

  final Ref _ref;
  final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  Future<void> start() async {
    _sub = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(handle(uri)),
      onError: (Object e, StackTrace st) =>
          _log.warning('deep-link stream error', e, st),
    );
    final initial = await _appLinks.getInitialLink();
    if (initial != null) {
      await handle(initial);
    }
  }

  @visibleForTesting
  Future<void> handle(Uri uri) async {
    if (!_isAuthCallback(uri)) return;
    final inFlight = _ref.read(upgradeInFlightProvider) != null;
    // The cold getSessionFromUrl path installs the FORKED OAuth session and
    // persists its user_id. That is only safe when the active identity is
    // signed-out or anonymous. A keypair identity (or an OAuth session that
    // still keeps the keypair fallback) means this callback is a "link", not
    // a "replace" — even if the in-flight flag was already cleared by the
    // timeout. Route those through completeLink so a late callback recovers
    // the link instead of clobbering the keypair user_id (ADR-0042 §Flow A).
    if (inFlight || _wouldClobberKeypair()) {
      await _ref
          .read(accountUpgradeControllerProvider.notifier)
          .completeLink(uri);
      return;
    }
    try {
      await _ref.read(supabaseAuthAdapterProvider).completeOAuthSignIn(uri);
    } on Object catch (e, st) {
      _log.warning('cold-start oauth callback failed', e, st);
    }
  }

  bool _wouldClobberKeypair() {
    final session = _ref.read(authControllerProvider).value;
    return session is KeypairSession ||
        (session is OAuthSession && session.hasKeypairFallback);
  }

  bool _isAuthCallback(Uri uri) {
    final target = Uri.parse(kAuthCallback);
    return uri.scheme == target.scheme && uri.host == target.host;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}

/// App-lifetime [AuthDeepLinkService]. Constructed and started on first
/// read (the bootstrap eagerly reads it once after `Supabase.initialize`)
/// and kept alive for the process. Tests override it with a fake.
final authDeepLinkServiceProvider = Provider<AuthDeepLinkService>((ref) {
  final service = AuthDeepLinkService(ref);
  ref.onDispose(() => unawaited(service.dispose()));
  unawaited(service.start());
  return service;
});
