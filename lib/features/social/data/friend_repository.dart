import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/social/data/friend_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wrapper around the friend RPCs declared in
/// `supabase/migrations/20260507000001_social_graph.sql`. Every call is
/// authenticated; the SECURITY DEFINER functions on the server guard
/// the rest. The repository deliberately does no caching — providers
/// invalidate on writes, the UI consumes the FutureProvider.
class FriendRepository {
  FriendRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<List<FriendCandidate>> searchByUsername(String query) async {
    final rows = await _client.rpc<List<dynamic>>(
      'friend_search_by_username',
      params: <String, dynamic>{'p_query': query},
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(FriendCandidate.fromRow)
        .toList(growable: false);
  }

  Future<List<FriendEntry>> listForCaller() async {
    final rows = await _client.rpc<List<dynamic>>('friend_list_for_caller');
    return rows
        .cast<Map<String, dynamic>>()
        .map(FriendEntry.fromRow)
        .toList(growable: false);
  }

  Future<void> sendRequest(String targetUserId) {
    return _client.rpc<void>(
      'friend_request_send',
      params: <String, dynamic>{'p_target_user_id': targetUserId},
    );
  }

  Future<void> acceptRequest(String otherUserId) {
    return _client.rpc<void>(
      'friend_request_accept',
      params: <String, dynamic>{'p_other_user_id': otherUserId},
    );
  }

  Future<void> rejectRequest(String otherUserId) {
    return _client.rpc<void>(
      'friend_request_reject',
      params: <String, dynamic>{'p_other_user_id': otherUserId},
    );
  }

  Future<void> remove(String otherUserId) {
    return _client.rpc<void>(
      'friend_remove',
      params: <String, dynamic>{'p_other_user_id': otherUserId},
    );
  }
}

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  return FriendRepository(client: Supabase.instance.client);
});
