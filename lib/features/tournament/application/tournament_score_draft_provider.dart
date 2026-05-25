import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/dao/tournament_score_draft_dao.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// DAO that persists per-match per-consensus-round score drafts.
final tournamentScoreDraftDaoProvider =
    Provider<TournamentScoreDraftDao>((ref) {
  return TournamentScoreDraftDao(ref.watch(appDatabaseProvider));
});

typedef TournamentScoreDraftKey = ({
  TournamentMatchId matchId,
  int consensusRound,
});

/// Loads the persisted draft for `(matchId, consensusRound)`. Returns
/// `null` when no draft exists yet (DSCORE-20).
// Riverpod's family-provider type names are not part of the public API,
// so we suppress the lint here and rely on the generic args for inference.
// ignore: specify_nonobvious_property_types
final tournamentScoreDraftProvider =
    FutureProvider.family<List<SetScore>?, TournamentScoreDraftKey>(
  (ref, key) => ref
      .read(tournamentScoreDraftDaoProvider)
      .load(key.matchId, key.consensusRound),
);
