import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/dao/app_settings_dao.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
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
    final cooldownUntil = await _readCooldown(settings, nickname);
    final now = DateTime.now().toUtc();
    if (cooldownUntil != null && cooldownUntil.isAfter(now)) {
      state = RestoreState.cooldown(until: cooldownUntil);
      return;
    }

    state = const RestoreState.restoring();
    final backup = ref.read(keypairBackupRepositoryProvider);
    final keypairStorage = ref.read(keypairStorageProvider);

    try {
      final restored = await backup.restoreBackup(
        nickname: nickname,
        passphrase: passphrase,
      );
      await keypairStorage.save(restored.privateKey);
      await _resetFailures(settings, nickname);
      // The actual sign-in (challenge / verify) happens in
      // KeypairSigningService — not here. RestoreController exists to
      // get the private key onto the device; the controller layer
      // chains in the signing step.
      state = const RestoreState.done(userId: 'restored-pending-signin');
    } on KeypairRestoreFailed catch (e) {
      final newFailures = await _incrementFailures(settings, nickname);
      if (newFailures >= _maxFailures) {
        final until = now.add(_cooldown);
        await _writeCooldown(settings, nickname, until);
        state = RestoreState.cooldown(until: until);
      } else {
        state = RestoreState.failed(reason: e.message);
      }
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
