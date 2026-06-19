import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Select seam: returns the `tournament_stages` rows (`node_id`, `config`) for
/// one tournament. Tests inject a capturing fake instead of a live client.
typedef StageTiebreakSelectCaller = Future<List<dynamic>> Function(
  String tournamentId,
);

/// Read-only repository that resolves the per-stage-node KO tiebreak method
/// (P5.3d / ADR-0034 §2). Lightweight (its own select seam, not the big
/// [TournamentRemote] port) so it adds no surface to the port or its fakes.
///
/// A stage-graph KO match uses ITS node's configured `ko_tiebreak_method`; the
/// live match-scoring falls back to the tournament-level method when the node
/// has none (or for classic, non-stage tournaments where this map is empty).
class StageTiebreakRepository {
  /// Production constructor: a scoped select on `tournament_stages`.
  StageTiebreakRepository({required SupabaseClient client})
      : _select = ((tid) => client
            .from(tableName)
            .select('node_id, config')
            .eq('tournament_id', tid));

  /// Test seam: build around a captured select caller, no live client.
  StageTiebreakRepository.withSelect(this._select);

  final StageTiebreakSelectCaller _select;

  static const String tableName = 'tournament_stages';

  /// Maps each stage node id to its configured KO tiebreak method, omitting
  /// nodes without one. Empty for classic (non-stage) tournaments.
  Future<Map<String, KoTiebreakMethod>> fetchMethods(TournamentId id) async {
    final rows = await _select(id.value);
    final out = <String, KoTiebreakMethod>{};
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final nodeId = row['node_id'] as String?;
      final config = row['config'];
      if (nodeId == null || config is! Map) continue;
      final method =
          koTiebreakMethodFromConfig(Map<String, Object?>.from(config));
      if (method != null) out[nodeId] = method;
    }
    return out;
  }
}

final stageTiebreakRepositoryProvider = Provider<StageTiebreakRepository>(
  (ref) => StageTiebreakRepository(client: Supabase.instance.client),
);

/// Per-tournament map of stage node id -> configured KO tiebreak method.
/// Cached by tournament; empty for classic tournaments.
// ignore: specify_nonobvious_property_types
final tournamentStageTiebreakMethodsProvider =
    FutureProvider.family<Map<String, KoTiebreakMethod>, TournamentId>(
  (ref, id) => ref.read(stageTiebreakRepositoryProvider).fetchMethods(id),
);
