import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';
import 'package:kubb_app/features/training/data/finisseur_repository.dart';

class ActiveFinisseurNotifier
    extends AsyncNotifier<ActiveFinisseurState?> {
  @override
  Future<ActiveFinisseurState?> build() async => null;

  FinisseurRepository get _repo => ref.read(finisseurRepositoryProvider);

  Future<void> startSession({
    required String playerId,
    required int field,
    required int base,
  }) async {
    final s = await _repo.startFinisseur(
      playerId: playerId,
      field: field,
      base: base,
    );
    state = AsyncData(
      ActiveFinisseurState(
        sessionId: s.id,
        field: field,
        base: base,
        sticks: List<StickResult>.filled(
          ActiveFinisseurState.totalSticks,
          const StickResult(),
        ),
        currentIndex: 0,
        startedAt: s.startedAt,
      ),
    );
  }

  void updateCurrentStick(StickResult patch) {
    final s = state.value;
    if (s == null) return;
    state = AsyncData(s.copyWithCurrent(patch));
  }

  /// Persists the current stick and advances to the next index. Returns true
  /// when the session is complete (i.e. the last stick was advanced).
  Future<bool> advance() async {
    final s = state.value;
    if (s == null) return false;
    await _repo.recordStick(
      sessionId: s.sessionId,
      stickIndex: s.currentIndex,
      result: s.current,
    );
    final next = s.currentIndex + 1;
    state = AsyncData(s.copyWithIndex(next));
    return next >= ActiveFinisseurState.totalSticks;
  }

  Future<void> complete() async {
    final s = state.value;
    if (s == null) return;
    await _repo.markCompleted(sessionId: s.sessionId);
    state = const AsyncData(null);
  }

  Future<void> abortAndDelete() async {
    final s = state.value;
    if (s == null) return;
    await _repo.discard(sessionId: s.sessionId);
    state = const AsyncData(null);
  }

  /// Drops the most recently committed stick and rewinds the index by one.
  /// The current (uncommitted) stick edits are discarded — back means "undo
  /// the last commit", not "preserve in-flight work".
  ///
  /// Returns false when there is nothing to roll back (already at stick 0).
  Future<bool> rollbackLastStick() async {
    final s = state.value;
    if (s == null) return false;
    if (s.currentIndex == 0) return false;
    final prev = s.currentIndex - 1;
    await _repo.deleteStickAt(sessionId: s.sessionId, stickIndex: prev);
    final restored = List<StickResult>.from(s.sticks);
    if (s.currentIndex < restored.length) {
      restored[s.currentIndex] = const StickResult();
    }
    restored[prev] = const StickResult();
    state = AsyncData(
      ActiveFinisseurState(
        sessionId: s.sessionId,
        field: s.field,
        base: s.base,
        sticks: restored,
        currentIndex: prev,
        startedAt: s.startedAt,
      ),
    );
    return true;
  }
}

final activeFinisseurProvider =
    AsyncNotifierProvider<ActiveFinisseurNotifier, ActiveFinisseurState?>(
  ActiveFinisseurNotifier.new,
);
