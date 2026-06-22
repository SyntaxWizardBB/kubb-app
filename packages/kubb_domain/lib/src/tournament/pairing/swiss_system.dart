import 'package:kubb_domain/src/tournament/pairing.dart';

typedef _Pair = (String a, String b);

/// Swiss-System pairing per FR-FMT-4 and schoch-swiss-pairing-buchholz-spec.md
/// §6: standings ordered by points → Buchholz (§5) → stable start number, then
/// Monrad adjacent pairing with rematch-avoiding backtracking. The start number
/// is the participant's position in the `participants` list passed to
/// [planRound] — a tournament-stable seed, not a per-round RNG (spec §6.4 forbids
/// per-round randomness). A forced rematch (marked `repeated: true`) only
/// happens when no rematch-free pairing exists at all.
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
  /// roster and all previously completed matches. Fully deterministic: the
  /// same (participants, completedMatches) always yield the same pairings.
  /// [tournamentId] is kept for call-site stability but no longer seeds any
  /// randomness. The participant's index in [participants] is its stable
  /// start number, used as the final tiebreak (spec §6.1 key 3).
  PlannedRound planRound({
    required List<String> participants,
    required List<MatchResult> completedMatches,
    required int roundNumber,
    required String tournamentId,
  }) {
    if (participants.isEmpty) {
      throw ArgumentError('participants must not be empty');
    }
    final startNumber = {
      for (var i = 0; i < participants.length; i++) participants[i]: i,
    };
    final ordered = _sortByTiebreaks(participants, completedMatches, startNumber);
    final played = _playedSet(completedMatches);

    final pool = List<String>.of(ordered);
    String? byeId;
    if (pool.length.isOdd) {
      byeId = _selectBye(ordered, completedMatches);
      pool.remove(byeId);
    }

    final pairs = _pairClean(pool, played) ?? _pairForced(pool);
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
    Map<String, int> startNumber,
  ) {
    final points = {for (final id in ids) id: _pointsOf(id, matches)};
    final buch = {for (final id in ids) id: buchholz.scoreFor(id, matches)};
    return List<String>.of(ids)
      ..sort((a, b) {
        final byPts = points[b]!.compareTo(points[a]!);
        if (byPts != 0) return byPts;
        final byBuch = buch[b]!.compareTo(buch[a]!);
        if (byBuch != 0) return byBuch;
        return startNumber[a]!.compareTo(startNumber[b]!);
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

  /// Monrad adjacent pairing with rematch-avoiding backtracking (spec §6.2).
  /// Pairs the standings head with the nearest player below it that it has not
  /// yet met, backtracking when a greedy choice would strand a later player
  /// into a forced rematch. Returns `null` only when no rematch-free pairing
  /// of the whole pool exists.
  List<_Pair>? _pairClean(List<String> pool, Set<String> played) {
    if (pool.isEmpty) return const [];
    final head = pool.first;
    for (var i = 1; i < pool.length; i++) {
      final candidate = pool[i];
      if (played.contains(_key(head, candidate))) continue;
      final rest = [...pool.sublist(1, i), ...pool.sublist(i + 1)];
      final tail = _pairClean(rest, played);
      if (tail != null) return [(head, candidate), ...tail];
    }
    return null;
  }

  /// Forced fallback: pair top-to-bottom regardless of repeats.
  List<_Pair> _pairForced(List<String> pool) => [
        for (var i = 0; i + 1 < pool.length; i += 2) (pool[i], pool[i + 1]),
      ];
}
