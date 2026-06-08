import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/player/data/player_elo_ratings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads `public.player_ratings` for a single user. Read-only: there are no
/// writes, RPCs or migrations here (ELO is written exclusively by SECURITY
/// DEFINER triggers).
///
/// Visibility is enforced server-side by RLS (migration
/// `20261221000000_player_ratings_discipline_rls.sql`): the tournament row is
/// always returned, the personal row appears ONLY when RLS grants it
/// (owner / accepted friend). Never re-implement that gate here — the absence
/// of a `personal` row in the result is the signal that it must stay hidden.
class PlayerRatingsRepository {
  PlayerRatingsRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<PlayerEloRatings> ratingsFor(String userId) async {
    final rows =
        await _client.from('player_ratings').select().eq('user_id', userId);
    return PlayerEloRatings.fromRows(rows.cast<Map<String, dynamic>>());
  }
}

final playerRatingsRepositoryProvider = Provider<PlayerRatingsRepository>((ref) {
  return PlayerRatingsRepository(client: Supabase.instance.client);
});
