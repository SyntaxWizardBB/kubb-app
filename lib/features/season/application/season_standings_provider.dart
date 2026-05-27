import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One row of the season-standings table (OD-M5-06 A). `displayName`
/// falls back to a short id until T11 surfaces a profile join.
@immutable
class SeasonStandingsRow {
  const SeasonStandingsRow({
    required this.participantId,
    required this.displayName,
    required this.totalPoints,
    required this.tournamentCount,
    this.leagueId,
  });

  final String participantId;
  final String displayName;
  final double totalPoints;
  final int tournamentCount;
  final String? leagueId;
}

/// `season_get` read-model, pre-sorted Σ desc → tournamentCount desc →
/// displayName asc (OD-M5-06 A).
@immutable
class SeasonStandings {
  const SeasonStandings({required this.rows});

  final List<SeasonStandingsRow> rows;

  /// Distinct, non-null league ids — feeds the Liga-Filter dropdown.
  List<String> get leagueIds {
    final ids = <String>{
      for (final r in rows)
        if (r.leagueId != null) r.leagueId!,
    };
    return List.unmodifiable(ids.toList()..sort());
  }
}

/// Stub repository: T11's full `SeasonRepository` replaces this on
/// Wave-Merge. Wraps the `season_get` RPC (M5.2-T7).
class SeasonRepository {
  SeasonRepository(this._client);

  final SupabaseClient _client;

  Future<SeasonStandings> getSeason(String seasonId) async {
    final raw = await _client
        .rpc<dynamic>('season_get', params: {'p_season_id': seasonId});
    final envelope = (raw as Map<String, dynamic>?) ?? const {};
    final list = (envelope['standings'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final rows = list.map((m) {
      final pid = m['participant_id'] as String;
      return SeasonStandingsRow(
        participantId: pid,
        displayName: pid.length <= 8 ? pid : pid.substring(0, 8),
        totalPoints: (m['total_points'] as num?)?.toDouble() ?? 0,
        tournamentCount: (m['tournament_count'] as num?)?.toInt() ?? 0,
        leagueId: m['league_id'] as String?,
      );
    }).toList()
      ..sort((a, b) {
        final t = b.totalPoints.compareTo(a.totalPoints);
        if (t != 0) return t;
        final c = b.tournamentCount.compareTo(a.tournamentCount);
        if (c != 0) return c;
        return a.displayName.compareTo(b.displayName);
      });
    return SeasonStandings(rows: List.unmodifiable(rows));
  }
}

final seasonRepositoryProvider = Provider<SeasonRepository>(
  (ref) => SeasonRepository(Supabase.instance.client),
);

/// AsyncValue family keyed by `seasonId`. Screen pull-to-refresh
/// invalidates the matching entry. The generic family type is unwieldy
/// and not load-bearing at call sites, hence the ignore.
//
// ignore: specify_nonobvious_property_types
final seasonStandingsProvider =
    FutureProvider.family<SeasonStandings, String>((ref, seasonId) async {
  return ref.read(seasonRepositoryProvider).getSeason(seasonId);
});
