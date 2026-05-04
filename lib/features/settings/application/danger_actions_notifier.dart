import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';

/// Glue for the destructive settings action. Sessions reset is a hard delete
/// via DAO scoped to the active user. Account deletion lives in the auth
/// feature now (DeleteAccountScreen + AccountDeletionController), so this
/// notifier only owns the session-reset path.
class DangerActionsNotifier {
  DangerActionsNotifier(this._ref);

  final Ref _ref;

  Future<void> resetSessions() async {
    final profile = _ref.read(displayProfileProvider);
    if (profile == null) return;
    final db = _ref.read(appDatabaseProvider);
    await db.sessionDao.deleteAllForPlayer(profile.userId);
  }
}

final dangerActionsProvider = Provider<DangerActionsNotifier>((ref) {
  return DangerActionsNotifier(ref);
});
