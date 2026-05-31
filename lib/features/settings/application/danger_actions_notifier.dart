import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/training/application/cloud_training_provider.dart';
import 'package:kubb_app/features/training/data/cloud_training_repository.dart';
import 'package:logging/logging.dart';

final _log = Logger('settings.danger');

/// Glue for the destructive settings action. Sessions reset is a hard delete
/// via DAO scoped to the active user. Account deletion lives in the auth
/// feature now (DeleteAccountScreen + AccountDeletionController), so this
/// notifier only owns the session-reset path.
class DangerActionsNotifier {
  DangerActionsNotifier(this._ref);

  final Ref _ref;

  /// Wipes the user's training sessions — both the local drift rows and the
  /// server-stored cloud aggregates. The cloud delete is best-effort: a
  /// transient network/RLS failure must not block the local reset.
  Future<void> resetSessions() async {
    final profile = _ref.read(displayProfileProvider);
    if (profile == null) return;
    final db = _ref.read(appDatabaseProvider);
    await db.sessionDao.deleteAllForUser(profile.userId);
    try {
      await _ref
          .read(cloudTrainingRepositoryProvider)
          .deleteAllForUser(profile.userId);
      _ref.invalidate(myTrainingSessionsProvider);
    } on Object catch (e) {
      _log.warning('cloud session reset failed (local reset kept)', e);
    }
  }
}

final dangerActionsProvider = Provider<DangerActionsNotifier>((ref) {
  return DangerActionsNotifier(ref);
});
