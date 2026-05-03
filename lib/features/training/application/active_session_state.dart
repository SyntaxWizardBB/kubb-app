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

  ActiveSessionState copyWith({int? hits, int? misses, int? helis}) {
    return ActiveSessionState(
      sessionId: sessionId,
      distance: distance,
      throwTarget: throwTarget,
      hits: hits ?? this.hits,
      misses: misses ?? this.misses,
      helis: helis ?? this.helis,
      startedAt: startedAt,
    );
  }
}
