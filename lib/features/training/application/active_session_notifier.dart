import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/features/achievements/application/badge_unlock_listener.dart';
import 'package:kubb_app/features/training/application/active_session_state.dart';
import 'package:kubb_app/features/training/data/training_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:logging/logging.dart';

const _hit = 'hit';
const _miss = 'miss';
const _heli = 'heli';

class ActiveSessionNotifier extends AsyncNotifier<ActiveSessionState?> {
  @override
  Future<ActiveSessionState?> build() async => null;

  TrainingRepository get _repo => ref.read(trainingRepositoryProvider);

  /// Serializes every mutating call so concurrent double-taps cannot
  /// observe a stale snapshot of [state] across `await` boundaries.
  Completer<void>? _inFlight;

  /// True while a mutating call holds the in-flight lock. Surface so the
  /// UI can grey out tap pads instead of racing the notifier.
  bool get isLocked => _inFlight != null;

  Future<T> _serialize<T>(Future<T> Function() op) async {
    while (_inFlight != null) {
      await _inFlight!.future;
    }
    final gate = Completer<void>();
    _inFlight = gate;
    try {
      return await op();
    } finally {
      _inFlight = null;
      gate.complete();
    }
  }

  Future<void> startSession({
    required String playerId,
    required double distance,
    int? throwTarget,
  }) {
    return _serialize(() async {
      final s = await _repo.startSession(
        playerId: playerId,
        distance: distance,
        throwTarget: throwTarget,
      );
      state = AsyncData(_hydrate(s, 0, 0, 0));
    });
  }

  Future<void> recordHit() => _append(_hit);
  Future<void> recordMiss() => _append(_miss);
  Future<void> recordHeli() => _append(_heli);

  Future<void> undoLast(String kind) => _serialize(() => _withActive((s) async {
        await _repo.softDeleteLastEvent(sessionId: s.sessionId, kind: kind);
        // Re-read state after await: another serialized op may have
        // bumped counters in the meantime.
        final fresh = state.value ?? s;
        state = AsyncData(_bump(fresh, kind, -1));
      }));

  Future<void> complete() => _serialize(() => _withActive((s) async {
        await _repo.markCompleted(sessionId: s.sessionId);
        await _fireBadgeEvaluation(s);
        state = const AsyncData(null);
      }));

  /// Best-effort post-complete hook: builds the cumulative
  /// [BadgeSessionSummary] from the persisted store and hands it to
  /// the badge listener. Failures are logged only — badge persistence
  /// must never block a successful `markCompleted`.
  Future<void> _fireBadgeEvaluation(ActiveSessionState s) async {
    try {
      final db = ref.read(appDatabaseProvider);
      // Resolve the owning player via the row we just completed; the
      // `allCompletedForUser` query keys off `playerId`, not session id.
      final justCompleted = await db.sessionDao.getById(s.sessionId);
      if (justCompleted == null) return;
      final all =
          await db.sessionDao.allCompletedForUser(justCompleted.playerId);
      final eventDao = db.sessionEventDao;
      var totalHits = 0;
      var totalHelis = 0;
      final distances = <double>{};
      for (final session in all) {
        totalHits += await eventDao.countByKind(session.id, _hit);
        totalHelis += await eventDao.countByKind(session.id, _heli);
        distances.add(session.distanceMeters);
      }
      final context = BadgeTriggerContext(
        sniperHits: totalHits,
        sniperMaxStreak: s.hits,
        heliHits: totalHelis,
        distinctDistances: distances.length,
      );
      await ref.read(badgeUnlockListenerProvider).evaluateAfterSession(
            BadgeSessionSummary(
              sourceSessionId: s.sessionId,
              context: context,
            ),
          );
    } on Object catch (e, st) {
      _log.warning('badge evaluation failed after session complete', e, st);
    }
  }

  static final Logger _log = Logger('ActiveSessionNotifier');

  Future<void> abortAndDelete() => _serialize(() => _withActive((s) async {
        await _repo.discard(sessionId: s.sessionId);
        state = const AsyncData(null);
      }));

  Future<void> resumeFromCrash(String sessionId) {
    return _serialize(() async {
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
    });
  }

  Future<void> _append(String kind) =>
      _serialize(() => _withActive((s) async {
            await _repo.appendEvent(sessionId: s.sessionId, kind: kind);
            // Re-read state after await so we bump from the freshest
            // counter snapshot, not from the one captured before the DB
            // write completed.
            final fresh = state.value ?? s;
            state = AsyncData(_bump(fresh, kind, 1));
          }));

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
