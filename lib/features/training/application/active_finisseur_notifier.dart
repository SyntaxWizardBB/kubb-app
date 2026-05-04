import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';
import 'package:kubb_app/features/training/data/finisseur_repository.dart';

/// Outcome of [ActiveFinisseurNotifier.advance].
///
/// - [carryOn]: nothing special — keep filling sticks.
/// - [done]: session is over (won or lost). The caller persists and routes to
///   the summary.
/// - [needsContinueDecision]: stock 6 was just spent without a win and the
///   "continue beyond sticks" setting is on. The UI must ask the player
///   whether to continue or give up; the notifier waits for either
///   [ActiveFinisseurNotifier.continueBeyondStocks] or
///   [ActiveFinisseurNotifier.giveUp] before doing anything.
enum FinisseurAdvanceOutcome { carryOn, done, needsContinueDecision }

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

  /// Persists the current stick, advances the index, and recomputes the next
  /// phase. Returns the outcome so the UI knows whether to navigate, ask, or
  /// keep going.
  Future<FinisseurAdvanceOutcome> advance() async {
    final s = state.value;
    if (s == null) return FinisseurAdvanceOutcome.carryOn;
    await _repo.recordStick(
      sessionId: s.sessionId,
      stickIndex: s.currentIndex,
      result: s.current,
    );
    final next = s.currentIndex + 1;
    var nextState = s.copyWithIndex(next);

    final settings = ref.read(appSettingsProvider).value ?? const AppSettings();
    final won = _hasWon(nextState, settings);
    if (won) {
      state = AsyncData(nextState.copyWith(phase: FinisseurPhase.field));
      return FinisseurAdvanceOutcome.done;
    }

    // Out of sticks: either ask the player to continue, or end as a loss.
    if (next >= ActiveFinisseurState.totalSticks &&
        !nextState.continuedBeyondSticks) {
      if (settings.allowContinueBeyondSticks) {
        state = AsyncData(
          nextState.copyWith(phase: FinisseurPhase.awaitingContinueDecision),
        );
        return FinisseurAdvanceOutcome.needsContinueDecision;
      }
      state = AsyncData(nextState.copyWith(phase: FinisseurPhase.field));
      return FinisseurAdvanceOutcome.done;
    }

    // In Verlängerung: grow the buffer so the new index has a slot to write
    // into. Without this, currentIndex outruns sticks.length and updates
    // become silent no-ops.
    if (nextState.continuedBeyondSticks &&
        nextState.currentIndex >= nextState.sticks.length) {
      nextState = nextState.copyWith(
        sticks: List<StickResult>.from(nextState.sticks)
          ..add(const StickResult()),
      );
    }

    // Still has sticks left — pick the right phase for the next stick.
    nextState = _ensurePhase(nextState, settings);
    state = AsyncData(nextState);
    return FinisseurAdvanceOutcome.carryOn;
  }

  /// Player decided to keep going past stock 6. Grow the stick buffer by one
  /// and rerun the phase logic.
  Future<void> continueBeyondStocks() async {
    final s = state.value;
    if (s == null) return;
    final settings =
        ref.read(appSettingsProvider).value ?? const AppSettings();
    final extended = List<StickResult>.from(s.sticks)
      ..add(const StickResult());
    var next = s.copyWith(
      sticks: extended,
      continuedBeyondSticks: true,
      phase: FinisseurPhase.field,
    );
    next = _ensurePhase(next, settings);
    state = AsyncData(next);
  }

  /// Player gave up after stock 6. Persist as completed (failed) and clear.
  Future<void> giveUp() async {
    final s = state.value;
    if (s == null) return;
    await _repo.markCompleted(sessionId: s.sessionId);
    state = const AsyncData(null);
  }

  bool _hasWon(ActiveFinisseurState s, AppSettings settings) {
    final committed = s.sticks.take(s.currentIndex);
    final fieldDown = committed.fold<int>(0, (a, x) => a + x.fieldHits);
    final baseDown = committed.where((x) => x.eightMHit).length;
    final kingHit = committed.any((x) => x.king?.hit ?? false);
    final allKubbsDown = fieldDown >= s.field && baseDown >= s.base;
    if (settings.kingThrowTracking) return kingHit;
    return allKubbsDown;
  }

  ActiveFinisseurState _ensurePhase(
    ActiveFinisseurState s,
    AppSettings settings,
  ) {
    if (s.currentIndex >= s.sticks.length) return s;
    final remField = s.remainingFieldBeforeCurrent;
    final remBase = s.remainingBaseBeforeCurrent;
    if (remField > 0) {
      return s.copyWith(phase: FinisseurPhase.field);
    }
    if (remBase > 0) {
      return s.copyWith(phase: FinisseurPhase.base);
    }
    if (settings.kingThrowTracking) {
      // Pre-seed a king result so the player can just tap Stock-abschliessen
      // to record a hit (the default outcome). Tapping verfehlt overrides it
      // before commit.
      final pre = s.current.king == null
          ? s.copyWithCurrent(
              s.current.copyWith(king: const KingResult(hit: true)),
            )
          : s;
      return pre.copyWith(phase: FinisseurPhase.king);
    }
    // King tracking off + nothing left: should not happen — _hasWon catches
    // it. Fall back to field phase to keep the type total.
    return s.copyWith(phase: FinisseurPhase.field);
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
  /// In Verlängerung the appended slot is removed; rolling back from the
  /// first Verlängerungs-stick takes the player to stock 6 with edits
  /// restored and unsets `continuedBeyondSticks` so the continue-decision
  /// can re-trigger.
  ///
  /// Returns false when there is nothing to roll back (already at stick 0).
  Future<bool> rollbackLastStick() async {
    final s = state.value;
    if (s == null) return false;
    if (s.currentIndex == 0) return false;
    final prev = s.currentIndex - 1;
    await _repo.deleteStickAt(sessionId: s.sessionId, stickIndex: prev);
    final restored = List<StickResult>.from(s.sticks);
    // Drop any appended Verlängerungs-slot beyond the new current index so
    // the buffer never carries trailing empty slots.
    while (restored.length > ActiveFinisseurState.totalSticks &&
        restored.length > prev + 1) {
      restored.removeLast();
    }
    if (prev < restored.length) {
      restored[prev] = const StickResult();
    }
    final stillBeyondSticks = prev >= ActiveFinisseurState.totalSticks;
    final settings =
        ref.read(appSettingsProvider).value ?? const AppSettings();
    var next = s.copyWith(
      sticks: restored,
      currentIndex: prev,
      continuedBeyondSticks: stillBeyondSticks && s.continuedBeyondSticks,
    );
    next = _ensurePhase(next, settings);
    state = AsyncData(next);
    return true;
  }
}

final activeFinisseurProvider =
    AsyncNotifierProvider<ActiveFinisseurNotifier, ActiveFinisseurState?>(
  ActiveFinisseurNotifier.new,
);
