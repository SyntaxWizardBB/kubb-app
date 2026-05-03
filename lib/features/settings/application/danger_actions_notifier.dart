import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';

/// Glue for the two destructive settings actions. Sessions reset is hard
/// delete via DAO; profile delete first nukes sessions, then the player row
/// itself, so the bootstrap redirect picks up the missing profile and routes
/// back to onboarding.
class DangerActionsNotifier {
  DangerActionsNotifier(this._ref);

  final Ref _ref;

  Future<void> resetSessions() async {
    final profile = await _ref.read(currentProfileProvider.future);
    if (profile == null) return;
    final db = _ref.read(appDatabaseProvider);
    await db.sessionDao.deleteAllForPlayer(profile.id);
  }

  Future<void> deleteProfile() async {
    final profile = await _ref.read(currentProfileProvider.future);
    if (profile == null) return;
    final db = _ref.read(appDatabaseProvider);
    await db.sessionDao.deleteAllForPlayer(profile.id);
    await _ref.read(playerRepositoryProvider).delete(profile.id);
  }
}

final dangerActionsProvider = Provider<DangerActionsNotifier>((ref) {
  return DangerActionsNotifier(ref);
});
