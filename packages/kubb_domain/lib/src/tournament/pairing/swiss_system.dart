import 'dart:math' as math;

import 'package:kubb_domain/src/tournament/pairing.dart';

typedef _Pair = (String a, String b);

/// Swiss-System pairing per FR-FMT-4 with Buchholz → Direct-Encounter →
/// Random(seed) tiebreaks (OD-M5-01 Empfehlung B). Greedy top-to-bottom
/// with bounded backtracking (depth ≤3, R-M5.1-2); falls back to a forced
/// rematch marked `repeated: true` when no rematch-free pairing exists.
class SwissSystemStrategy implements PairingStrategy {
  const SwissSystemStrategy({this.buchholz = const BuchholzCalculator()});

  final BuchholzCalculator buchholz;

  @override
  PairingStrategyKind get kind => PairingStrategyKind.swissSystem;

  /// Legacy single-list entry point (round 1, no prior matches).
  @override
  List<PlannedRound> plan(List<String> participantIds) => [
        planRound(
          participants: participantIds,
          completedMatches: const [],
          roundNumber: 1,
          tournamentId: '',
        ),
      ];

  /// Primary stateful API: emits the next [PlannedRound] given the current
  /// roster and all previously completed matches. Deterministic for a given
  /// (tournamentId, roundNumber) pair via the seeded RNG.
  PlannedRound planRound({
    required List<String> participants,
    required List<MatchResult> completedMatches,
    required int roundNumber,
    required String tournamentId,
  }) {
    if (participants.isEmpty) {
      throw ArgumentError('participants must not be empty');
    }
    final rng = math.Random(tournamentId.hashCode ^ roundNumber);
    final ordered = _sortByTiebreaks(participants, completedMatches, rng);
    final played = _playedSet(completedMatches);

    final pool = List<String>.of(ordered);
    String? byeId;
    if (pool.length.isOdd) {
      byeId = _selectBye(ordered, completedMatches);
      pool.remove(byeId);
    }

    final pairs = _pairClean(pool, played, 0) ?? _pairForced(pool);
    return PlannedRound(
      roundNumber: roundNumber,
      pairings: List.unmodifiable([
        for (final (a, b) in pairs)
          PlannedPairing(
            participantA: a,
            participantB: b,
            repeated: played.contains(_key(a, b)),
          ),
        if (byeId != null) PlannedPairing(participantA: byeId),
      ]),
    );
  }

  List<String> _sortByTiebreaks(
    List<String> ids,
    List<MatchResult> matches,
    math.Random rng,
  ) {
    final points = {for (final id in ids) id: _pointsOf(id, matches)};
    final buch = {for (final id in ids) id: buchholz.scoreFor(id, matches)};
    final h2h = _headToHead(ids, matches);
    final jitter = {for (final id in ids) id: rng.nextDouble()};
    return List<String>.of(ids)
      ..sort((a, b) {
        final byPts = points[b]!.compareTo(points[a]!);
        if (byPts != 0) return byPts;
        final byBuch = buch[b]!.compareTo(buch[a]!);
        if (byBuch != 0) return byBuch;
        final byH2h = h2h[b]!.compareTo(h2h[a]!);
        if (byH2h != 0) return byH2h;
        return jitter[a]!.compareTo(jitter[b]!);
      });
  }

  int _pointsOf(String id, List<MatchResult> matches) {
    var p = 0;
    for (final m in matches) {
      if (m.participantA == id) p += m.pointsA;
      if (m.participantB == id) p += m.pointsB;
    }
    return p;
  }

  Map<String, int> _headToHead(List<String> ids, List<MatchResult> matches) {
    final h2h = {for (final id in ids) id: 0};
    for (final m in matches) {
      if (m.isBye) continue;
      if (m.pointsA > m.pointsB) {
        h2h[m.participantA] = h2h[m.participantA]! + m.pointsA;
      } else if (m.pointsB > m.pointsA) {
        h2h[m.participantB!] = h2h[m.participantB!]! + m.pointsB;
      }
    }
    return h2h;
  }

  Set<String> _playedSet(List<MatchResult> matches) => {
        for (final m in matches)
          if (!m.isBye) _key(m.participantA, m.participantB!),
      };

  String _key(String a, String b) =>
      a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

  String _selectBye(List<String> ordered, List<MatchResult> matches) {
    final hadBye = {
      for (final m in matches)
        if (m.isBye) m.participantA,
    };
    for (final id in ordered.reversed) {
      if (!hadBye.contains(id)) return id;
    }
    return ordered.last;
  }

  /// Greedy + bounded backtracking. Returns `null` when no rematch-free
  /// pairing exists within depth budget 3 (R-M5.1-2).
  List<_Pair>? _pairClean(List<String> pool, Set<String> played, int depth) {
    if (pool.isEmpty) return const [];
    if (depth > 3) return null;
    final head = pool.first;
    for (var i = 1; i < pool.length; i++) {
      final candidate = pool[i];
      if (played.contains(_key(head, candidate))) continue;
      final rest = [...pool.sublist(1, i), ...pool.sublist(i + 1)];
      final tail = _pairClean(rest, played, depth + 1);
      if (tail != null) return [(head, candidate), ...tail];
    }
    return null;
  }

  /// Forced fallback: pair top-to-bottom regardless of repeats.
  List<_Pair> _pairForced(List<String> pool) => [
        for (var i = 0; i + 1 < pool.length; i += 2) (pool[i], pool[i + 1]),
      ];
}
