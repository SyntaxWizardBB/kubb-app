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
}

final activeFinisseurProvider =
    AsyncNotifierProvider<ActiveFinisseurNotifier, ActiveFinisseurState?>(
  ActiveFinisseurNotifier.new,
);
