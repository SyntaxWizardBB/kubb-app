import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/dao/app_settings_dao.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/keypair_signing_service.dart';

part 'restore_controller.freezed.dart';

/// State for the keypair-restore flow on a fresh install.
///
/// Per ADR-0011 the user enters a BIP-39 mnemonic; the client derives
/// the keypair locally and proves ownership via the existing challenge
/// /sign /verify flow. There is no nickname lookup and no encrypted
/// backup to fetch.
@freezed
class RestoreState with _$RestoreState {
  const factory RestoreState.idle() = _RestoreIdle;
  const factory RestoreState.cooldown({required DateTime until}) =
      _RestoreCooldown;
  const factory RestoreState.restoring() = _Restoring;
  const factory RestoreState.done({required String userId}) = _RestoreDone;
  const factory RestoreState.failed({required String reason}) = _RestoreFailed;
}

/// Three failed attempts in a row trigger a 30-second cooldown. The
/// counter is keyed off the mnemonic-derived public key so a typo on
/// one phrase doesn't lock the user out of a different account, while
/// repeated bad guesses on the same phrase still throttle.
const int _maxFailures = 3;
const Duration _cooldown = Duration(seconds: 30);

final restoreControllerProvider =
    NotifierProvider<RestoreController, RestoreState>(
        RestoreController.new);

class RestoreController extends Notifier<RestoreState> {
  /// Authoritative clear-the-cooldown timer. Set whenever we transition
  /// into `RestoreState.cooldown(...)`; fires once when `until` is due
  /// and flips the state back to `idle`. Independent of any UI widget —
  /// the cooldown badge is purely cosmetic from the controller's
  /// perspective. Solves the regression where a stale closure / race
  /// in the badge's post-frame callback could leave the banner stuck
  /// at "0s".
  Timer? _expiryTimer;

  @override
  RestoreState build() {
    ref.onDispose(() {
      _expiryTimer?.cancel();
      _expiryTimer = null;
    });
    return const RestoreState.idle();
  }

  void _enterCooldown(DateTime until) {
    state = RestoreState.cooldown(until: until);
    _scheduleExpiry(until);
  }

  void _scheduleExpiry(DateTime until) {
    _expiryTimer?.cancel();
    final delay = until.difference(DateTime.now().toUtc());
    if (delay <= Duration.zero) {
      // Cooldown is already past — flip immediately on the next tick so
      // the assignment doesn't collide with a build that's running now.
      scheduleMicrotask(_clearIfStillCooldown);
      return;
    }
    // Add a small grace so we never fire a hair before the badge's own
    // tick rounds to zero — keeps the visual countdown coherent with
    // the state flip.
    _expiryTimer = Timer(
      delay + const Duration(milliseconds: 100),
      _clearIfStillCooldown,
    );
  }

  void _clearIfStillCooldown() {
    _expiryTimer = null;
    final current = state;
    if (current is _RestoreCooldown) {
      if (!current.until.isAfter(DateTime.now().toUtc())) {
        state = const RestoreState.idle();
      }
    }
  }

  /// Restore a session from a BIP-39 mnemonic. The mnemonic is
  /// validated locally; if the checksum fails we never hit the network.
  Future<void> restore({required String mnemonic}) async {
    // Drop any pending cooldown-expiry timer up front. This covers two
    // cases: (1) the user retried before the previous timer fired, and
    // (2) the controller persisted across a sign-out so a stale timer
    // from a previous session could still be queued.
    _expiryTimer?.cancel();
    _expiryTimer = null;

    final settings = ref.read(appDatabaseProvider).appSettingsDao;
    final telemetry = ref.read(authTelemetryProvider);
    final crypto = ref.read(cryptoServiceProvider);

    if (!crypto.isValidBip39Mnemonic(mnemonic)) {
      telemetry.restoreAttempted(
        success: false,
        reasonCode: 'mnemonic_invalid',
      );
      state = const RestoreState.failed(reason: 'mnemonic_invalid');
      return;
    }

    // Derive the public key locally so we can scope cooldown entries
    // to the specific mnemonic the user typed (not to the device).
    final keypair = await crypto.keypairFromMnemonic(mnemonic);
    final keyId = base64Encode(keypair.publicKey);

    final cooldownUntil = await _readCooldown(settings, keyId);
    final now = DateTime.now().toUtc();
    if (cooldownUntil != null && cooldownUntil.isAfter(now)) {
      telemetry.restoreAttempted(
        success: false,
        reasonCode: 'cooldown_active',
      );
      _enterCooldown(cooldownUntil);
      return;
    }

    state = const RestoreState.restoring();
    final keypairStorage = ref.read(keypairStorageProvider);
    final signingService = ref.read(keypairSigningServiceProvider);

    try {
      await keypairStorage.save(keypair.privateKey);
      // Chain straight into challenge / sign / verify — the verify
      // call hydrates the Supabase session, so by the time we
      // transition to RestoreState.done the auth-state stream has
      // already seen the new keypair session.
      final verified = await signingService.signInWithChallenge();
      await _resetFailures(settings, keyId);
      telemetry.restoreAttempted(success: true);
      state = RestoreState.done(userId: verified.userId);
    } on Object catch (e, st) {
      // Sign-in step failed — typical reasons:
      //   * server has no account for this public key (the mnemonic is
      //     a valid BIP-39 phrase but does not correspond to any
      //     registered keypair — user typoed words, or memorised a
      //     phrase from a different account)
      //   * network down
      //   * server configuration drift.
      //
      // Critical: WIPE the just-saved private key out of secure
      // storage. Otherwise the failed attempt's bytes linger and any
      // subsequent flow that calls keypairStorage.load() (an automatic
      // session bootstrap, a retry path) would sign with the wrong
      // key. The next restore attempt overwrites anyway, but the
      // window in between can confuse anything that boots in that
      // gap.
      try {
        await keypairStorage.clear();
      } on Object catch (_) {
        // Best-effort cleanup. Swallow — we are already on the error
        // path; surfacing a secondary cleanup error would mask the
        // original signin failure.
      }

      final reasonCode = _classifyRestoreError(e);
      // Diagnostic for adb logcat — when the user reports "restore
      // doesn't find my account", this is the line that tells us
      // which derived public key the server rejected.
      // ignore: avoid_print
      print('RESTORE $reasonCode for pubkey=$keyId: $e\n$st');
      final newFailures = await _incrementFailures(settings, keyId);
      if (newFailures >= _maxFailures) {
        final until = now.add(_cooldown);
        await _writeCooldown(settings, keyId, until);
        telemetry.restoreAttempted(
          success: false,
          reasonCode: 'cooldown_triggered',
        );
        _enterCooldown(until);
      } else {
        telemetry.restoreAttempted(
          success: false,
          reasonCode: reasonCode,
        );
        state = RestoreState.failed(reason: reasonCode);
      }
    }
  }

  /// Map an exception from `signInWithChallenge` to a stable reason
  /// code the UI can render. Distinguishes "valid mnemonic but no
  /// matching account" from generic network failures so the screen
  /// can show actionable copy.
  String _classifyRestoreError(Object e) {
    final s = e.toString();
    if (s.contains('no_account_for_public_key')) {
      return 'no_account_for_mnemonic';
    }
    if (s.contains('signature_invalid')) {
      return 'signature_invalid';
    }
    if (s.contains('challenge_expired') ||
        s.contains('challenge_not_found')) {
      return 'challenge_failed';
    }
    return 'signin_failed';
  }

  /// Called by the cooldown badge when its countdown reaches zero. We
  /// flip the state back to idle so the form re-renders and the badge
  /// disappears.
  void clearIfExpired() {
    state.maybeWhen(
      cooldown: (until) {
        if (!until.isAfter(DateTime.now().toUtc())) {
          state = const RestoreState.idle();
        }
      },
      orElse: () {},
    );
  }

  Future<int> _incrementFailures(AppSettingsDao dao, String keyId) async {
    final key = 'restore_failure_$keyId';
    final raw = await dao.get(key);
    final entry = raw == null
        ? <String, dynamic>{'count': 0}
        : jsonDecode(raw) as Map<String, dynamic>;
    final next = ((entry['count'] as int?) ?? 0) + 1;
    entry['count'] = next;
    await dao.save(key, jsonEncode(entry));
    return next;
  }

  Future<void> _resetFailures(AppSettingsDao dao, String keyId) async {
    await dao.save('restore_failure_$keyId', jsonEncode({'count': 0}));
  }

  Future<void> _writeCooldown(
    AppSettingsDao dao,
    String keyId,
    DateTime until,
  ) async {
    final key = 'restore_failure_$keyId';
    final raw = await dao.get(key);
    final entry = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    entry['cooldownUntil'] = until.toIso8601String();
    entry['count'] = 0;
    await dao.save(key, jsonEncode(entry));
  }

  Future<DateTime?> _readCooldown(AppSettingsDao dao, String keyId) async {
    final raw = await dao.get('restore_failure_$keyId');
    if (raw == null) return null;
    final entry = jsonDecode(raw) as Map<String, dynamic>;
    final until = entry['cooldownUntil'] as String?;
    if (until == null) return null;
    return DateTime.parse(until);
  }
}
