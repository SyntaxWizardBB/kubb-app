import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// One row of the conflict comparison table: both teams' proposals for
/// a single set inside the current consensus round. Either side may be
/// null when only one team has submitted so far.
class TournamentSetProposalPair {
  const TournamentSetProposalPair({
    required this.setNumber,
    required this.teamA,
    required this.teamB,
  });

  final int setNumber;
  final TournamentSetScoreProposal? teamA;
  final TournamentSetScoreProposal? teamB;

  bool get hasDiff {
    final a = teamA?.score;
    final b = teamB?.score;
    if (a == null || b == null) return false;
    return a != b;
  }
}

/// Snapshot of all proposals submitted for one match in the current
/// consensus round, grouped into A/B pairs by set number.
///
/// M1 backs this with an in-memory holder because the
/// `tournament_match_get` RPC does not yet surface the proposal list.
/// The router and screen are wired through this provider so the M2
/// server-side change can land without touching presentation.
class TournamentConflictSnapshot {
  const TournamentConflictSnapshot({
    required this.consensusRound,
    required this.pairs,
  });

  final int consensusRound;
  final List<TournamentSetProposalPair> pairs;

  static const empty = TournamentConflictSnapshot(
    consensusRound: 1,
    pairs: <TournamentSetProposalPair>[],
  );
}

/// Groups a flat list of proposals by set number and resolves the
/// per-side assignment using a stable submitter ordering. The first
/// distinct submitter seen becomes Team A, the second Team B.
TournamentConflictSnapshot buildConflictSnapshot(
  List<TournamentSetScoreProposal> proposals,
) {
  if (proposals.isEmpty) return TournamentConflictSnapshot.empty;
  final round = proposals.first.consensusRound;
  final submitterOrder = <String>[];
  for (final p in proposals) {
    final id = p.submitterUserId.value;
    if (!submitterOrder.contains(id)) submitterOrder.add(id);
  }
  final teamAId = submitterOrder.isNotEmpty ? submitterOrder[0] : null;
  final teamBId = submitterOrder.length > 1 ? submitterOrder[1] : null;
  final bySet = <int, List<TournamentSetScoreProposal>>{};
  for (final p in proposals.where((p) => p.consensusRound == round)) {
    bySet.putIfAbsent(p.setNumber, () => <TournamentSetScoreProposal>[]).add(p);
  }
  final sortedSets = bySet.keys.toList()..sort();
  final pairs = <TournamentSetProposalPair>[
    for (final n in sortedSets)
      TournamentSetProposalPair(
        setNumber: n,
        teamA: bySet[n]!.firstWhere(
          (p) => p.submitterUserId.value == teamAId,
          orElse: () => bySet[n]!.first,
        ),
        teamB: teamBId == null
            ? null
            : bySet[n]!
                .where((p) => p.submitterUserId.value == teamBId)
                .firstOrNull,
      ),
  ];
  return TournamentConflictSnapshot(consensusRound: round, pairs: pairs);
}

/// Conflict view-model for a given match. Overridable in tests; the
/// production wiring lands together with the server-side proposal feed
/// in M2. Until then the default returns the empty snapshot.
// ignore: specify_nonobvious_property_types
final tournamentConflictProvider =
    FutureProvider.family<TournamentConflictSnapshot, TournamentMatchId>(
        (ref, id) async {
  return TournamentConflictSnapshot.empty;
});

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
