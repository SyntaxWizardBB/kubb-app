import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-only client for the System-4 tournament-statistics RPCs
/// (`20261245000000_tournament_statistics.sql` +
/// `20261246000000_tournament_stat_participants.sql`). All four functions
/// are public (granted to anon + authenticated) and consider only
/// `status='finalized'` tournaments, so no auth plumbing is needed here.
///
/// The STABLE participant id is `COALESCE(team_id, user_id)` — identical to
/// `season_standings_awards.participant_id` and `tournament_ranking_get`.

/// One series as returned by `tournament_series_list`.
@immutable
class TournamentSeriesSummary {
  const TournamentSeriesSummary({
    required this.seriesKey,
    required this.seriesLabel,
    required this.editionCount,
  });

  factory TournamentSeriesSummary.fromRow(Map<String, dynamic> row) {
    return TournamentSeriesSummary(
      seriesKey: (row['series_key'] as String?) ?? '',
      seriesLabel: (row['series_label'] as String?) ??
          (row['series_key'] as String?) ??
          '',
      editionCount: (row['edition_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String seriesKey;
  final String seriesLabel;
  final int editionCount;
}

/// One finalized edition inside [TournamentSeriesStats].
@immutable
class TournamentSeriesEdition {
  const TournamentSeriesEdition({
    required this.tournamentId,
    required this.displayName,
    required this.completedAt,
    required this.fieldSize,
    required this.winnerParticipantId,
  });

  factory TournamentSeriesEdition.fromJson(Map<String, dynamic> json) {
    return TournamentSeriesEdition(
      tournamentId: (json['tournament_id'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ?? '',
      completedAt: _parseDate(json['completed_at']),
      fieldSize: (json['field_size'] as num?)?.toInt() ?? 0,
      winnerParticipantId: json['winner_participant_id'] as String?,
    );
  }

  final String tournamentId;
  final String displayName;
  final DateTime? completedAt;
  final int fieldSize;
  final String? winnerParticipantId;
}

/// One bucket of the per-series placement distribution.
@immutable
class TournamentPlacementBucket {
  const TournamentPlacementBucket({
    required this.placement,
    required this.count,
  });

  factory TournamentPlacementBucket.fromJson(Map<String, dynamic> json) {
    return TournamentPlacementBucket(
      placement: (json['placement'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  final int placement;
  final int count;
}

/// One own-placement entry inside [TournamentParticipantSeriesPerf].
@immutable
class TournamentParticipantPlacement {
  const TournamentParticipantPlacement({
    required this.tournamentId,
    required this.placement,
  });

  factory TournamentParticipantPlacement.fromJson(Map<String, dynamic> json) {
    return TournamentParticipantPlacement(
      tournamentId: (json['tournament_id'] as String?) ?? '',
      placement: (json['placement'] as num?)?.toInt() ?? 0,
    );
  }

  final String tournamentId;
  final int placement;
}

/// The optional `participant` block of `tournament_series_stats` — only
/// present when a participant id was passed to the RPC.
@immutable
class TournamentParticipantSeriesPerf {
  const TournamentParticipantSeriesPerf({
    required this.placements,
    required this.bestPlacement,
    required this.avgPlacement,
    required this.editionsPlayed,
  });

  factory TournamentParticipantSeriesPerf.fromJson(Map<String, dynamic> json) {
    final placements = (json['placements'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>()
        .map(TournamentParticipantPlacement.fromJson)
        .toList(growable: false);
    return TournamentParticipantSeriesPerf(
      placements: placements,
      bestPlacement: (json['best_placement'] as num?)?.toInt(),
      avgPlacement: (json['avg_placement'] as num?)?.toDouble(),
      editionsPlayed: (json['editions_played'] as num?)?.toInt() ?? 0,
    );
  }

  final List<TournamentParticipantPlacement> placements;
  final int? bestPlacement;
  final double? avgPlacement;
  final int editionsPlayed;
}

/// Full result of `tournament_series_stats`.
@immutable
class TournamentSeriesStats {
  const TournamentSeriesStats({
    required this.editions,
    required this.placementDistribution,
    required this.participant,
  });

  factory TournamentSeriesStats.fromJson(Map<String, dynamic> json) {
    final editions = (json['editions'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>()
        .map(TournamentSeriesEdition.fromJson)
        .toList(growable: false);
    final dist =
        (json['placement_distribution'] as List<dynamic>? ?? <dynamic>[])
            .cast<Map<String, dynamic>>()
            .map(TournamentPlacementBucket.fromJson)
            .toList(growable: false);
    final part = json['participant'] as Map<String, dynamic>?;
    return TournamentSeriesStats(
      editions: editions,
      placementDistribution: dist,
      participant:
          part == null ? null : TournamentParticipantSeriesPerf.fromJson(part),
    );
  }

  final List<TournamentSeriesEdition> editions;
  final List<TournamentPlacementBucket> placementDistribution;

  /// Own performance, present only when the stats were requested for a
  /// specific participant id (null otherwise).
  final TournamentParticipantSeriesPerf? participant;
}

/// Result of `tournament_head_to_head`.
@immutable
class TournamentHeadToHead {
  const TournamentHeadToHead({
    required this.totalMatches,
    required this.aWins,
    required this.bWins,
    required this.koMatches,
    required this.koAWins,
    required this.koBWins,
    required this.aWinRate,
  });

  factory TournamentHeadToHead.fromJson(Map<String, dynamic> json) {
    return TournamentHeadToHead(
      totalMatches: (json['total_matches'] as num?)?.toInt() ?? 0,
      aWins: (json['a_wins'] as num?)?.toInt() ?? 0,
      bWins: (json['b_wins'] as num?)?.toInt() ?? 0,
      koMatches: (json['ko_matches'] as num?)?.toInt() ?? 0,
      koAWins: (json['ko_a_wins'] as num?)?.toInt() ?? 0,
      koBWins: (json['ko_b_wins'] as num?)?.toInt() ?? 0,
      aWinRate: (json['a_win_rate'] as num?)?.toDouble() ?? 0,
    );
  }

  final int totalMatches;
  final int aWins;
  final int bWins;
  final int koMatches;
  final int koAWins;
  final int koBWins;
  final double aWinRate;

  /// Matches with no recorded winner on either side (e.g. unfinished),
  /// derived: total − a − b. Never negative.
  int get draws {
    final d = totalMatches - aWins - bWins;
    return d < 0 ? 0 : d;
  }
}

/// One row of the head-to-head participant directory
/// (`tournament_stat_participants`).
@immutable
class TournamentStatParticipant {
  const TournamentStatParticipant({
    required this.participantId,
    required this.displayName,
    required this.isTeam,
    required this.editions,
  });

  factory TournamentStatParticipant.fromRow(Map<String, dynamic> row) {
    final id = (row['participant_id'] as String?) ?? '';
    return TournamentStatParticipant(
      participantId: id,
      displayName: (row['display_name'] as String?) ?? id,
      isTeam: (row['is_team'] as bool?) ?? false,
      editions: (row['editions'] as num?)?.toInt() ?? 0,
    );
  }

  final String participantId;
  final String displayName;
  final bool isTeam;
  final int editions;
}

/// Wraps the four System-4 statistics RPCs. Read-only / public.
class TournamentStatisticsRepository {
  TournamentStatisticsRepository({required SupabaseClient client})
      : _client = client;

  final SupabaseClient _client;

  static const String seriesListRpc = 'tournament_series_list';
  static const String seriesStatsRpc = 'tournament_series_stats';
  static const String headToHeadRpc = 'tournament_head_to_head';
  static const String participantsRpc = 'tournament_stat_participants';

  /// All tournament series derived from finalized tournaments.
  Future<List<TournamentSeriesSummary>> listSeries() async {
    final rows = await _client.rpc<List<dynamic>>(seriesListRpc);
    return rows
        .cast<Map<String, dynamic>>()
        .map(TournamentSeriesSummary.fromRow)
        .toList(growable: false);
  }

  /// Statistics for one series. When [participantId] is given the result
  /// carries the own-performance block.
  Future<TournamentSeriesStats> seriesStats(
    String seriesKey, {
    String? participantId,
  }) async {
    final params = <String, dynamic>{'p_series_key': seriesKey};
    if (participantId != null) params['p_participant_id'] = participantId;
    final json = await _client.rpc<Map<String, dynamic>>(
      seriesStatsRpc,
      params: params,
    );
    return TournamentSeriesStats.fromJson(json);
  }

  /// Head-to-head between two stable participant ids.
  Future<TournamentHeadToHead> headToHead(String a, String b) async {
    final json = await _client.rpc<Map<String, dynamic>>(
      headToHeadRpc,
      params: <String, dynamic>{'p_a': a, 'p_b': b},
    );
    return TournamentHeadToHead.fromJson(json);
  }

  /// Directory of selectable participants for the head-to-head picker.
  Future<List<TournamentStatParticipant>> searchParticipants(
    String query,
  ) async {
    final rows = await _client.rpc<List<dynamic>>(
      participantsRpc,
      params: <String, dynamic>{'p_query': query},
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(TournamentStatParticipant.fromRow)
        .toList(growable: false);
  }
}

DateTime? _parseDate(Object? raw) {
  if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
  return null;
}

final tournamentStatisticsRepositoryProvider =
    Provider<TournamentStatisticsRepository>(
  (ref) => TournamentStatisticsRepository(client: Supabase.instance.client),
);

/// All series (global, refetched on invalidate / pull-to-refresh).
final tournamentSeriesListProvider =
    FutureProvider<List<TournamentSeriesSummary>>(
  (ref) async => ref.read(tournamentStatisticsRepositoryProvider).listSeries(),
);

/// Key for [tournamentSeriesStatsProvider]: a series plus an optional
/// participant id whose own performance to include.
@immutable
class SeriesStatsArgs {
  const SeriesStatsArgs({required this.seriesKey, this.participantId});

  final String seriesKey;
  final String? participantId;

  @override
  bool operator ==(Object other) =>
      other is SeriesStatsArgs &&
      other.seriesKey == seriesKey &&
      other.participantId == participantId;

  @override
  int get hashCode => Object.hash(seriesKey, participantId);
}

//
// ignore: specify_nonobvious_property_types
final tournamentSeriesStatsProvider =
    FutureProvider.family<TournamentSeriesStats, SeriesStatsArgs>(
  (ref, args) async => ref
      .read(tournamentStatisticsRepositoryProvider)
      .seriesStats(args.seriesKey, participantId: args.participantId),
);

/// Key for [tournamentHeadToHeadProvider]: an ordered participant pair.
@immutable
class HeadToHeadArgs {
  const HeadToHeadArgs({required this.a, required this.b});

  final String a;
  final String b;

  @override
  bool operator ==(Object other) =>
      other is HeadToHeadArgs && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);
}

//
// ignore: specify_nonobvious_property_types
final tournamentHeadToHeadProvider =
    FutureProvider.family<TournamentHeadToHead, HeadToHeadArgs>(
  (ref, args) async =>
      ref.read(tournamentStatisticsRepositoryProvider).headToHead(args.a, args.b),
);

/// Participant directory keyed by the (lower-cased) search query.
//
// ignore: specify_nonobvious_property_types
final tournamentStatParticipantsProvider =
    FutureProvider.family<List<TournamentStatParticipant>, String>(
  (ref, query) async =>
      ref.read(tournamentStatisticsRepositoryProvider).searchParticipants(query),
);
