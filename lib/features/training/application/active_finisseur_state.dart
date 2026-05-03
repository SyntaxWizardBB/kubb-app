/// Position des Königs beim Königswurf — beschreibt, ob das Wurfholz "oben"
/// (klassisch über dem Bein) oder "unten" (zwischen den Beinen durch) den
/// König trifft.
enum KingPosition { oben, unten }

class KingResult {
  const KingResult({required this.hit, this.position = KingPosition.oben});

  final bool hit;
  final KingPosition position;

  KingResult copyWith({bool? hit, KingPosition? position}) =>
      KingResult(hit: hit ?? this.hit, position: position ?? this.position);
}

class StickResult {
  const StickResult({
    this.fieldHits = 0,
    this.eightMHit = false,
    this.heli = false,
    this.king,
    this.penalty1 = 0,
    this.penalty2 = 0,
  });

  final int fieldHits;
  final bool eightMHit;
  final bool heli;
  final KingResult? king;
  final int penalty1;
  final int penalty2;

  bool get isUntouched =>
      fieldHits == 0 && !eightMHit && !heli && king == null &&
      penalty1 == 0 && penalty2 == 0;

  StickResult copyWith({
    int? fieldHits,
    bool? eightMHit,
    bool? heli,
    KingResult? king,
    bool clearKing = false,
    int? penalty1,
    int? penalty2,
  }) {
    return StickResult(
      fieldHits: fieldHits ?? this.fieldHits,
      eightMHit: eightMHit ?? this.eightMHit,
      heli: heli ?? this.heli,
      king: clearKing ? null : (king ?? this.king),
      penalty1: penalty1 ?? this.penalty1,
      penalty2: penalty2 ?? this.penalty2,
    );
  }
}

/// Snapshot the UI consumes while a finisseur session is running.
///
/// `sticks` is the rolling buffer of all six sticks (default empty/untouched).
/// `currentIndex` points at the stick currently being filled (0..5). When
/// `currentIndex` equals `sticks.length` the session is past its last stick
/// and ready to be finalised.
class ActiveFinisseurState {
  const ActiveFinisseurState({
    required this.sessionId,
    required this.field,
    required this.base,
    required this.sticks,
    required this.currentIndex,
    required this.startedAt,
  });

  static const int totalSticks = 6;

  final String sessionId;
  final int field;
  final int base;
  final List<StickResult> sticks;
  final int currentIndex;
  final DateTime startedAt;

  StickResult get current =>
      currentIndex < sticks.length ? sticks[currentIndex] : const StickResult();

  bool get isLastStick => currentIndex >= totalSticks - 1;
  bool get isFinished => currentIndex >= totalSticks;

  int get fieldDownPrior {
    var sum = 0;
    for (var i = 0; i < currentIndex && i < sticks.length; i++) {
      sum += sticks[i].fieldHits;
    }
    return sum;
  }

  int get baseDownPrior {
    var sum = 0;
    for (var i = 0; i < currentIndex && i < sticks.length; i++) {
      if (sticks[i].eightMHit) sum++;
    }
    return sum;
  }

  int get remainingFieldBeforeCurrent =>
      (field - fieldDownPrior).clamp(0, field);
  int get remainingBaseBeforeCurrent => (base - baseDownPrior).clamp(0, base);

  ActiveFinisseurState copyWithCurrent(StickResult patch) {
    final copy = List<StickResult>.from(sticks);
    if (currentIndex < copy.length) copy[currentIndex] = patch;
    return ActiveFinisseurState(
      sessionId: sessionId,
      field: field,
      base: base,
      sticks: copy,
      currentIndex: currentIndex,
      startedAt: startedAt,
    );
  }

  ActiveFinisseurState copyWithIndex(int next) {
    return ActiveFinisseurState(
      sessionId: sessionId,
      field: field,
      base: base,
      sticks: sticks,
      currentIndex: next,
      startedAt: startedAt,
    );
  }
}
