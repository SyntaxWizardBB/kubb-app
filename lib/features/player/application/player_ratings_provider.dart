import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/player/data/player_elo_ratings.dart';
import 'package:kubb_app/features/player/data/player_ratings_repository.dart';

/// ELO ratings for a single player, keyed by user_id. The same provider feeds
/// both profile screens — the own profile (own user_id) and a friend's profile
/// (their user_id).
///
/// Visibility is governed by RLS, not by the client: the result contains a
/// `personal` row only when the viewer is the owner or an accepted friend. The
/// widget simply renders whatever disciplines came back.
// Riverpod's family-provider type names are not part of the public API, so we
// suppress the lint here and rely on the generic args for inference.
// ignore: specify_nonobvious_property_types
final playerRatingsProvider =
    FutureProvider.family<PlayerEloRatings, String>((ref, userId) async {
  return ref.read(playerRatingsRepositoryProvider).ratingsFor(userId);
});
