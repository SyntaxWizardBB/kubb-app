import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/social/data/group_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroupRepository {
  GroupRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<List<GroupListEntry>> listForCaller() async {
    final rows = await _client.rpc<List<dynamic>>('group_list_for_caller');
    return rows
        .cast<Map<String, dynamic>>()
        .map(GroupListEntry.fromRow)
        .toList(growable: false);
  }

  Future<List<GroupMember>> membersFor(String groupId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'group_members_for',
      params: <String, dynamic>{'p_group_id': groupId},
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(GroupMember.fromRow)
        .toList(growable: false);
  }

  Future<String> create(String name) async {
    // The RPC returns `jsonb` like `{"group_id": "<uuid>"}` — matches
    // the pattern used by every other write RPC in this codebase.
    final response = await _client.rpc<Map<String, dynamic>>(
      'group_create',
      params: <String, dynamic>{'p_name': name},
    );
    return response['group_id']! as String;
  }

  Future<void> rename(String groupId, String name) {
    return _client.rpc<void>(
      'group_rename',
      params: <String, dynamic>{'p_group_id': groupId, 'p_name': name},
    );
  }

  Future<void> delete(String groupId) {
    return _client.rpc<void>(
      'group_delete',
      params: <String, dynamic>{'p_group_id': groupId},
    );
  }

  Future<void> inviteMember(String groupId, String userId) {
    return _client.rpc<void>(
      'group_invite_member',
      params: <String, dynamic>{
        'p_group_id': groupId,
        'p_user_id': userId,
      },
    );
  }

  Future<void> removeMember(String groupId, String userId) {
    return _client.rpc<void>(
      'group_remove_member',
      params: <String, dynamic>{
        'p_group_id': groupId,
        'p_user_id': userId,
      },
    );
  }
}

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(client: Supabase.instance.client);
});
