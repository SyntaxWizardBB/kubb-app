import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Minimal value object backing the season list / detail tiles. The
/// season feature uses pragmatic CRUD (no dedicated `kubb_domain` port,
/// mirroring the team-feature convention) so we keep the row mapping
/// inline next to the repository instead of pulling in a separate
/// `season_models.dart`.
class Season {
  const Season({
    required this.id,
    required this.name,
    required this.status,
    this.leagueId,
    this.startsAt,
    this.endsAt,
  });

  factory Season.fromRow(Map<String, dynamic> row) => Season(
        id: row['id']! as String,
        name: row['name']! as String,
        status: row['status']! as String,
        leagueId: row['league_id'] as String?,
        startsAt: row['starts_at'] == null
            ? null
            : DateTime.parse(row['starts_at']! as String),
        endsAt: row['ends_at'] == null
            ? null
            : DateTime.parse(row['ends_at']! as String),
      );

  final String id;
  final String name;
  final String status;
  final String? leagueId;
  final DateTime? startsAt;
  final DateTime? endsAt;
}

/// Snapshot row from `season_tournaments` — tournament assignment with
/// frozen factors per ADR-0025 §4.
class SeasonTournament {
  const SeasonTournament({
    required this.seasonId,
    required this.tournamentId,
    required this.tournamentFactor,
    required this.leagueFactor,
  });

  factory SeasonTournament.fromRow(Map<String, dynamic> row) => SeasonTournament(
        seasonId: row['season_id']! as String,
        tournamentId: row['tournament_id']! as String,
        tournamentFactor: (row['tournament_factor']! as num).toDouble(),
        leagueFactor: (row['league_factor']! as num).toDouble(),
      );

  final String seasonId;
  final String tournamentId;
  final double tournamentFactor;
  final double leagueFactor;
}

/// Direct CRUD against `seasons` / `season_tournaments`. Writes rely on
/// the league-admin RLS policies declared in
/// `20260801000003_season_rls.sql`; reads of the consolidated detail
/// payload go through the `season_get` RPC added by T7.
class SeasonRepository {
  SeasonRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<List<Season>> listSeasons() async {
    final rows = await _client
        .from('seasons')
        .select('id, name, status, league_id, starts_at, ends_at')
        .order('created_at', ascending: false);
    return rows
        .cast<Map<String, dynamic>>()
        .map(Season.fromRow)
        .toList(growable: false);
  }

  Future<Season?> getSeason(String id) async {
    final response = await _client.rpc<Map<String, dynamic>?>(
      'season_get',
      params: <String, dynamic>{'p_season_id': id},
    );
    final header = response?['season'];
    if (header is! Map<String, dynamic>) return null;
    return Season.fromRow(header);
  }

  Future<String> createSeason({
    required String name,
    String? leagueId,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final row = await _client
        .from('seasons')
        .insert(<String, dynamic>{
          'name': name,
          'league_id': ?leagueId,
          'starts_at': ?startsAt?.toIso8601String().substring(0, 10),
          'ends_at': ?endsAt?.toIso8601String().substring(0, 10),
        })
        .select('id')
        .single();
    return row['id']! as String;
  }

  Future<void> updateStatus(String id, String status) async {
    await _client
        .from('seasons')
        .update(<String, dynamic>{'status': status}).eq('id', id);
  }

  Future<void> assignTournament(
    String seasonId,
    String tournamentId, {
    double tournamentFactor = 1.0,
    double leagueFactor = 1.0,
  }) async {
    await _client.from('season_tournaments').insert(<String, dynamic>{
      'season_id': seasonId,
      'tournament_id': tournamentId,
      'tournament_factor': tournamentFactor,
      'league_factor': leagueFactor,
    });
  }
}

final seasonRepositoryProvider = Provider<SeasonRepository>((ref) {
  return SeasonRepository(client: Supabase.instance.client);
});
