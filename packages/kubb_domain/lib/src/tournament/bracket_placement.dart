import 'package:kubb_domain/src/tournament/bracket.dart';

/// Builds the ordered tier list for a COMPLETED single-elimination tournament,
/// ready to feed `computeFinalRanking`.
///
/// Reuses [KoMatchRow] and [BracketPhase] from `bracket.dart`. The result is
/// suitable to flow directly into `computeFinalRanking(tiers, koRankCount, ...)`.
///
/// ## Tier order (best first)
/// 1. The single `finals` match: winner -> tier `[winner]` (rank 1), loser ->
///    tier `[loser]` (rank 2).
/// 2. Rank 3 / rank 4:
///    * If a `thirdPlace` match exists: its winner -> tier (rank 3), its loser
///      -> tier (rank 4) — two separate singleton tiers.
///    * Otherwise: the two losers of the HIGHEST `winners` round (the semifinal,
///      i.e. the largest `roundNumber` among the `winners` matches) form ONE
///      shared tier (shared rank 3, tier size 2).
/// 3. The remaining `winners` rounds, descending by `roundNumber` (quarterfinal,
///    then round-of-16, ...): the losers of each round form one tier each. A
///    later round (higher `roundNumber`) sits higher. The highest `winners`
///    round (the semifinal, max `roundNumber`) is already covered by step 2 and
///    is NOT emitted again here (step 3 iterates over `roundNumber <
///    maxWinnersRound`).
/// 4. The preliminary tail: entries from [prelimRanking] that appear in NO
///    `koMatch` as a real (non-null) `participantA`/`participantB`, in
///    `prelimRanking` order, each as its OWN tier, appended AFTER all KO tiers.
///
/// ## koRankCount
/// `koRankCount` = number of distinct REAL KO participants = the count of
/// distinct non-null values across all `participantA`/`participantB` of all
/// [koMatches] (BYE slots and null slots do not count). `N` (the whole field) =
/// `prelimRanking.length`. As a consequence of the documented assumption below
/// it holds that `4 <= koRankCount <= N`; this is documented, not enforced.
///
/// ## Loser determination (single-elim rules)
/// A played match yields a loser exactly when `isBye == false` AND both
/// `participantA != null && participantB != null` AND `winnerParticipantId` is
/// one of the two. The loser is the real participant that is NOT
/// `winnerParticipantId`. No loser entry is produced for a BYE match, a match
/// without two real participants, or a match with a null `winnerParticipantId`;
/// such matches are skipped for tier building. Phase assignment runs solely via
/// `phase` (`winners` / `finals` / `thirdPlace`); `roundNumber` only orders the
/// `winners` rounds.
///
/// ## Determinism
/// Stable, reproducible order: within a multi-element loser tier (the shared
/// semifinal tier and the per-round tiers of step 3) the ids are sorted by
/// their position in [prelimRanking] (best first). Identical input yields
/// identical output, regardless of the order of [koMatches].
///
/// ## Validation
/// Throws [ArgumentError] when [koMatches] is empty, when a real KO participant
/// is not contained in [prelimRanking], when [prelimRanking] contains
/// duplicates, when no `finals` match is present, or when the `finals` /
/// `thirdPlace` match is present but not completed.
///
/// ## Assumption (documented, NOT enforced)
/// The KO part has `>= 4` real participants and is a well-formed, fully
/// completed single-elim (exactly one `finals`, at most one `thirdPlace`) —
/// consistent with the SKV eligibility of `>= 8` (SKV §1). For `koRankCount <
/// 4` the downstream `computeFinalRanking` / `skvPointsForPlacement` would
/// throw (they require `4 <= koRankCount <= N`).
({List<List<String>> tiers, int koRankCount}) singleElimFinalTiers({
  required List<KoMatchRow> koMatches,
  required List<String> prelimRanking,
}) {
  // --- Validation ---
  if (koMatches.isEmpty) {
    throw ArgumentError.value(koMatches, 'koMatches', 'must not be empty');
  }
  final prelimSeen = <String>{};
  final prelimIndex = <String, int>{};
  for (var i = 0; i < prelimRanking.length; i++) {
    final id = prelimRanking[i];
    if (!prelimSeen.add(id)) {
      throw ArgumentError.value(
        id,
        'prelimRanking',
        'contains duplicate participantId',
      );
    }
    prelimIndex[id] = i;
  }

  // Collect distinct real KO participants across all matches.
  final koParticipants = <String>{};
  for (final m in koMatches) {
    if (m.participantA != null) koParticipants.add(m.participantA!);
    if (m.participantB != null) koParticipants.add(m.participantB!);
  }
  for (final id in koParticipants) {
    if (!prelimSeen.contains(id)) {
      throw ArgumentError.value(
        id,
        'koMatches',
        'KO participant is missing from prelimRanking',
      );
    }
  }
  final koRankCount = koParticipants.length;

  // --- Loser determination helper (single-elim rules) ---
  String? loserOf(KoMatchRow m) {
    if (m.isBye) return null;
    final a = m.participantA;
    final b = m.participantB;
    final w = m.winnerParticipantId;
    if (a == null || b == null || w == null) return null;
    if (w == a) return b;
    if (w == b) return a;
    return null; // winner is neither participant -> not a valid result
  }

  // Sort a set of ids by their preliminary rank (best first), deterministic.
  // Every loser fed here is a real KO participant and was validated to exist in
  // `prelimRanking` above, so `prelimIndex[...]` is always present.
  List<String> sortedByPrelim(Iterable<String> ids) {
    final list = ids.toList()
      ..sort((x, y) => prelimIndex[x]!.compareTo(prelimIndex[y]!));
    return list;
  }

  final tiers = <List<String>>[];

  // --- Step 1: finals match -> ranks 1 and 2. ---
  final finalsMatch = koMatches.firstWhere(
    (m) => m.phase == BracketPhase.finals,
    orElse: () => throw ArgumentError.value(
      koMatches,
      'koMatches',
      'no finals match found (expected a completed single-elim)',
    ),
  );
  final finalsWinner = finalsMatch.winnerParticipantId;
  final finalsLoser = loserOf(finalsMatch);
  if (finalsWinner == null || finalsLoser == null) {
    throw ArgumentError.value(
      finalsMatch,
      'koMatches',
      'finals match is not completed',
    );
  }
  tiers
    ..add(<String>[finalsWinner])
    ..add(<String>[finalsLoser]);

  // --- Winners rounds bookkeeping. ---
  final winnersMatches =
      koMatches.where((m) => m.phase == BracketPhase.winners).toList();
  final winnersRounds = winnersMatches.map((m) => m.roundNumber).toSet();
  final maxWinnersRound = winnersRounds.isEmpty
      ? null
      : winnersRounds.reduce((a, b) => a > b ? a : b);

  List<String> losersForRound(int round) {
    final losers = <String>[];
    for (final m in winnersMatches) {
      if (m.roundNumber != round) continue;
      final l = loserOf(m);
      if (l != null) losers.add(l);
    }
    return sortedByPrelim(losers);
  }

  // --- Step 2: ranks 3 / 4. ---
  final thirdPlaceMatch = koMatches
      .where((m) => m.phase == BracketPhase.thirdPlace)
      .toList();
  if (thirdPlaceMatch.isNotEmpty) {
    final tp = thirdPlaceMatch.first;
    final tpWinner = tp.winnerParticipantId;
    final tpLoser = loserOf(tp);
    if (tpWinner == null || tpLoser == null) {
      // A present-but-incomplete third-place match would silently drop both
      // semifinal losers (step 3 still skips `maxWinnersRound`). Fail fast here
      // — analogous to the finals completeness check above — instead of leaking
      // an undersized tier list into `computeFinalRanking`.
      throw ArgumentError.value(
        tp,
        'koMatches',
        'third-place match is not completed',
      );
    }
    tiers
      ..add(<String>[tpWinner])
      ..add(<String>[tpLoser]);
  } else if (maxWinnersRound != null) {
    // No third-place playoff: the two semifinal losers share rank 3.
    final semiLosers = losersForRound(maxWinnersRound);
    if (semiLosers.isNotEmpty) {
      tiers.add(semiLosers);
    }
  }

  // --- Step 3: remaining winners rounds, descending, below the semifinal. ---
  if (maxWinnersRound != null) {
    final lowerRounds = winnersRounds.where((r) => r < maxWinnersRound).toList()
      ..sort((a, b) => b.compareTo(a)); // descending
    for (final round in lowerRounds) {
      final losers = losersForRound(round);
      if (losers.isNotEmpty) tiers.add(losers);
    }
  }

  // --- Step 4: preliminary tail (non-qualified), one tier each, in order. ---
  for (final id in prelimRanking) {
    if (!koParticipants.contains(id)) {
      tiers.add(<String>[id]);
    }
  }

  return (tiers: tiers, koRankCount: koRankCount);
}
