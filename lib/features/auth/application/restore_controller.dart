import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/dao/app_settings_dao.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/keypair_signing_service.dart';
import 'package:kubb_app/features/auth/data/keypair_backup_repository.dart';

part 'restore_controller.freezed.dart';

/// State for the keypair-restore flow on a fresh install.
@freezed
class RestoreState with _$RestoreState {
  const factory RestoreState.idle() = _RestoreIdle;
  const factory RestoreState.cooldown({required DateTime until}) =
      _RestoreCooldown;
  const factory RestoreState.restoring() = _Restoring;
  const factory RestoreState.done({required String userId}) = _RestoreDone;
  const factory RestoreState.failed({required String reason}) = _RestoreFailed;
}

/// Three failed attempts per nickname trigger a 30-second cooldown
/// (per AK-4). Cooldown state is persisted in app_settings so a quick
/// app restart cannot bypass it.
const int _maxFailures = 3;
const Duration _cooldown = Duration(seconds: 30);

final restoreControllerProvider =
    NotifierProvider<RestoreController, RestoreState>(
        RestoreController.new);

class RestoreController extends Notifier<RestoreState> {
  @override
  RestoreState build() => const RestoreState.idle();

  Future<void> restore({
    required String nickname,
    required String passphrase,
  }) async {
    final settings = ref.read(appDatabaseProvider).appSettingsDao;
    final telemetry = ref.read(authTelemetryProvider);
    final cooldownUntil = await _readCooldown(settings, nickname);
    final now = DateTime.now().toUtc();
    if (cooldownUntil != null && cooldownUntil.isAfter(now)) {
      telemetry.restoreAttempted(
        success: false,
        reasonCode: 'cooldown_active',
      );
      state = RestoreState.cooldown(until: cooldownUntil);
      return;
    }

    state = const RestoreState.restoring();
    final backup = ref.read(keypairBackupRepositoryProvider);
    final keypairStorage = ref.read(keypairStorageProvider);
    final signingService = ref.read(keypairSigningServiceProvider);

    try {
      final restored = await backup.restoreBackup(
        nickname: nickname,
        passphrase: passphrase,
      );
      await keypairStorage.save(restored.privateKey);
      // Chain straight into challenge / sign / verify — the verify
      // call hydrates the Supabase session, so by the time we transition
      // to RestoreState.done the auth-state stream has already seen the
      // new keypair session and the AuthController has persisted it.
      final verified = await signingService.signInWithChallenge();
      await _resetFailures(settings, nickname);
      telemetry.restoreAttempted(success: true);
      state = RestoreState.done(userId: verified.userId);
    } on KeypairRestoreFailed catch (e) {
      final newFailures = await _incrementFailures(settings, nickname);
      if (newFailures >= _maxFailures) {
        final until = now.add(_cooldown);
        await _writeCooldown(settings, nickname, until);
        telemetry.restoreAttempted(
          success: false,
          reasonCode: 'cooldown_triggered',
        );
        state = RestoreState.cooldown(until: until);
      } else {
        // Reason code stays generic — `e.message` may carry server text
        // and must not land in telemetry.
        telemetry.restoreAttempted(
          success: false,
          reasonCode: 'restore_failed',
        );
        state = RestoreState.failed(reason: e.message);
      }
    } on Object catch (e) {
      // Sign-in step failed (network, signature mismatch, missing
      // server-side credential) — distinct from a wrong passphrase, so
      // we do not bump the cooldown counter. The user can retry the
      // same passphrase once connectivity is back.
      telemetry.restoreAttempted(
        success: false,
        reasonCode: 'signin_failed',
      );
      state = RestoreState.failed(reason: e.toString());
    }
  }

  Future<int> _incrementFailures(AppSettingsDao dao, String nickname) async {
    final key = 'restore_failure_$nickname';
    final raw = await dao.get(key);
    final entry = raw == null
        ? <String, dynamic>{'count': 0}
        : jsonDecode(raw) as Map<String, dynamic>;
    final next = ((entry['count'] as int?) ?? 0) + 1;
    entry['count'] = next;
    await dao.save(key, jsonEncode(entry));
    return next;
  }

  Future<void> _resetFailures(AppSettingsDao dao, String nickname) async {
    await dao.save('restore_failure_$nickname', jsonEncode({'count': 0}));
  }

  Future<void> _writeCooldown(
    AppSettingsDao dao,
    String nickname,
    DateTime until,
  ) async {
    final key = 'restore_failure_$nickname';
    final raw = await dao.get(key);
    final entry = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    entry['cooldownUntil'] = until.toIso8601String();
    entry['count'] = 0;
    await dao.save(key, jsonEncode(entry));
  }

  Future<DateTime?> _readCooldown(
    AppSettingsDao dao,
    String nickname,
  ) async {
    final raw = await dao.get('restore_failure_$nickname');
    if (raw == null) return null;
    final entry = jsonDecode(raw) as Map<String, dynamic>;
    final until = entry['cooldownUntil'] as String?;
    if (until == null) return null;
    return DateTime.parse(until);
  }
}
