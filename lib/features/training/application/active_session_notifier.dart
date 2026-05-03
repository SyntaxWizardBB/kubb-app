import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/features/training/application/active_session_state.dart';
import 'package:kubb_app/features/training/data/training_repository.dart';

const _hit = 'hit';
const _miss = 'miss';
const _heli = 'heli';

class ActiveSessionNotifier extends AsyncNotifier<ActiveSessionState?> {
  @override
  Future<ActiveSessionState?> build() async => null;

  TrainingRepository get _repo => ref.read(trainingRepositoryProvider);

  Future<void> startSession({
    required String playerId,
    required double distance,
    int? throwTarget,
  }) async {
    final s = await _repo.startSession(
      playerId: playerId,
      distance: distance,
      throwTarget: throwTarget,
    );
    state = AsyncData(_hydrate(s, 0, 0, 0));
  }

  Future<void> recordHit() => _append(_hit);
  Future<void> recordMiss() => _append(_miss);
  Future<void> recordHeli() => _append(_heli);

  Future<void> undoLast(String kind) => _withActive((s) async {
        await _repo.softDeleteLastEvent(sessionId: s.sessionId, kind: kind);
        state = AsyncData(_bump(s, kind, -1));
      });

  Future<void> complete() => _withActive((s) async {
        await _repo.markCompleted(sessionId: s.sessionId);
        state = const AsyncData(null);
      });

  Future<void> abortAndDelete() => _withActive((s) async {
        await _repo.discard(sessionId: s.sessionId);
        state = const AsyncData(null);
      });

  Future<void> resumeFromCrash(String sessionId) async {
    final db = ref.read(appDatabaseProvider);
    final s = await db.sessionDao.getById(sessionId);
    if (s == null) return;
    final ev = db.sessionEventDao;
    state = AsyncData(
      _hydrate(
        s,
        await ev.countByKind(sessionId, _hit),
        await ev.countByKind(sessionId, _miss),
        await ev.countByKind(sessionId, _heli),
      ),
    );
  }

  Future<void> _append(String kind) => _withActive((s) async {
        await _repo.appendEvent(sessionId: s.sessionId, kind: kind);
        state = AsyncData(_bump(s, kind, 1));
      });

  Future<void> _withActive(Future<void> Function(ActiveSessionState) op) async {
    final s = state.value;
    if (s != null) await op(s);
  }

  ActiveSessionState _hydrate(Session s, int hits, int misses, int helis) =>
      ActiveSessionState(
        sessionId: s.id,
        distance: s.distanceMeters,
        throwTarget: s.throwTarget,
        hits: hits,
        misses: misses,
        helis: helis,
        startedAt: s.startedAt,
      );

  ActiveSessionState _bump(ActiveSessionState s, String kind, int delta) {
    int c(int v) => v < 0 ? 0 : v;
    return switch (kind) {
      _hit => s.copyWith(hits: c(s.hits + delta)),
      _miss => s.copyWith(misses: c(s.misses + delta)),
      _heli => s.copyWith(helis: c(s.helis + delta)),
      _ => s,
    };
  }
}

final activeSessionProvider =
    AsyncNotifierProvider<ActiveSessionNotifier, ActiveSessionState?>(
  ActiveSessionNotifier.new,
);
