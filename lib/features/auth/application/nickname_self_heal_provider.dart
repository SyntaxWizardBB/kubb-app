import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/application/cloud_profile_provider.dart';
import 'package:kubb_app/features/auth/application/impersonation_controller.dart';
import 'package:kubb_app/features/auth/data/cloud_profile_repository.dart';
import 'package:logging/logging.dart';

final _log = Logger('nickname-self-heal');

/// Backfills the session display name for accounts that own a cloud profile
/// but whose `user_metadata` never received the chosen nickname.
///
/// This is the self-healing counterpart to the M2 onboarding fix: OAuth
/// accounts onboarded before the onboarding started mirroring the nickname
/// into user_metadata (and any keypair account whose metadata was never
/// seeded) carry an empty `session.displayName`, so `displayProfileProvider`
/// — home greeting, drawer, profile — shows a blank name while every
/// server-derived surface shows the real one. When such a session resolves
/// and the cloud profile has a real nickname, we write it into user_metadata
/// once, making the display name server-authoritative and device-independent
/// — identical to the keypair/anon setup.
///
/// Kept alive for the app's lifetime by a single `ref.watch` in `app.dart`.
final nicknameSelfHealProvider = Provider<NicknameSelfHeal>((ref) {
  final heal = NicknameSelfHeal(ref);
  ref.onDispose(heal.dispose);
  heal.start();
  return heal;
});

class NicknameSelfHeal {
  NicknameSelfHeal(this._ref);

  final Ref _ref;

  ProviderSubscription<AsyncValue<AuthSession>>? _authSub;

  /// user_ids we already healed (or found nothing to heal for) this run, so a
  /// re-emitted session — including the one our own updateNickname triggers —
  /// never spins a second write.
  final Set<String> _handled = <String>{};

  void start() {
    _authSub = _ref.listen<AsyncValue<AuthSession>>(
      authControllerProvider,
      (_, next) => unawaited(_onAuth(next.value)),
      fireImmediately: true,
    );
  }

  Future<void> _onAuth(AuthSession? session) async {
    if (session == null) return;
    if (session is! KeypairSession && session is! OAuthSession) return;
    // Never write to an impersonated target's account.
    if (_ref.read(impersonationProvider) != null) return;

    final userId = session.userId;
    if (userId == null || _handled.contains(userId)) return;

    final displayName = session.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) {
      // Already has a name — nothing to heal; remember so we skip cheaply.
      _handled.add(userId);
      return;
    }

    // The display name is blank. If the cloud profile carries a real
    // nickname, mirror it into user_metadata.
    final CloudProfile? profile;
    try {
      profile = await _ref.read(cloudProfileProvider.future);
    } on Object catch (e) {
      // Transient — leave it un-handled so a later emission retries.
      _log.fine('cloud profile unavailable, deferring self-heal: $e');
      return;
    }
    final nickname = profile?.nickname.trim() ?? '';
    if (nickname.isEmpty) return; // no profile yet (onboarding will seed it)

    // Re-check the guard: an in-flight emission may have handled it while the
    // profile query was awaited.
    if (_handled.contains(userId)) return;
    _handled.add(userId);
    try {
      await _ref.read(supabaseAuthAdapterProvider).updateNickname(nickname);
      _log.info('healed empty display name for $userId → "$nickname"');
    } on Object catch (e) {
      // Allow a retry on the next emission if the write failed.
      _handled.remove(userId);
      _log.warning('nickname self-heal write failed for $userId: $e');
    }
  }

  void dispose() {
    _authSub?.close();
  }
}
