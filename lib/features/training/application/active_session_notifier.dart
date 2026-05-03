import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Snapshot the UI consumes while a training session is running.
///
/// Counts (`hits`, `misses`, `helis`) are derived from non-corrected
/// `SessionEvent` rows in the underlying drift store. `throwTarget` mirrors
/// the configured target (null = open-ended).
class ActiveSessionState {
  const ActiveSessionState({
    required this.sessionId,
    required this.distance,
    required this.hits,
    required this.misses,
    required this.helis,
    required this.startedAt,
    this.throwTarget,
  });

  final String sessionId;
  final double distance;
  final int? throwTarget;
  final int hits;
  final int misses;
  final int helis;
  final DateTime startedAt;
}

/// Holds the lifecycle of the currently active sniper session.
///
/// Stub for M5-T2 (TDD). Real implementation lands in M5-T3; every method
/// throws `UnimplementedError` until then so the tests in
/// `test/features/training/application/active_session_notifier_test.dart`
/// compile and document the behaviour contract without accidentally
/// passing.
class ActiveSessionNotifier extends AsyncNotifier<ActiveSessionState?> {
  @override
  Future<ActiveSessionState?> build() {
    throw UnimplementedError('M5-T3 implements this');
  }

  Future<void> startSession({
    required String playerId,
    required double distance,
    int? throwTarget,
  }) =>
      throw UnimplementedError('M5-T3');

  Future<void> recordHit() => throw UnimplementedError('M5-T3');

  Future<void> recordMiss() => throw UnimplementedError('M5-T3');

  Future<void> recordHeli() => throw UnimplementedError('M5-T3');

  Future<void> undoLast(String kind) => throw UnimplementedError('M5-T3');

  Future<void> complete() => throw UnimplementedError('M5-T3');

  Future<void> abortAndDelete() => throw UnimplementedError('M5-T3');

  Future<void> resumeFromCrash(String sessionId) =>
      throw UnimplementedError('M5-T3');
}

final activeSessionProvider =
    AsyncNotifierProvider<ActiveSessionNotifier, ActiveSessionState?>(
  ActiveSessionNotifier.new,
);
