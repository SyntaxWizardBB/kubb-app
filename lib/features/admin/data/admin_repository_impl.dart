import 'package:kubb_app/features/admin/data/admin_models.dart';
import 'package:kubb_app/features/admin/data/admin_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [AdminRepository] over the live Supabase client. Each call is a single
/// `admin_*` RPC (migration 20261333000000); the server enforces
/// `caller_is_admin()` and audits every mutation.
class AdminRepositoryImpl implements AdminRepository {
  const AdminRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  Future<List<AdminUserRow>> listUsers({
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'admin_list_users',
      params: <String, dynamic>{
        'p_query': (query == null || query.trim().isEmpty) ? null : query.trim(),
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return rows
        .cast<Map<String, dynamic>>()
        .map(AdminUserRow.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> setCapability({
    required String userId,
    required String capability,
    required bool value,
  }) async {
    await _client.rpc<void>(
      'admin_set_capability',
      params: <String, dynamic>{
        'p_user_id': userId,
        'p_capability': capability,
        'p_value': value,
      },
    );
  }

  @override
  Future<void> setAccountStatus({
    required String userId,
    required bool suspended,
  }) async {
    await _client.rpc<void>(
      'admin_set_account_status',
      params: <String, dynamic>{
        'p_user_id': userId,
        'p_status': suspended ? 'suspended' : 'active',
      },
    );
  }

  @override
  Future<void> deleteAccount({required String userId}) async {
    await _client.rpc<void>(
      'admin_delete_account',
      params: <String, dynamic>{'p_user_id': userId},
    );
  }

  @override
  Future<String> sendInbox({
    required String userId,
    required String subject,
    required String body,
  }) async {
    final id = await _client.rpc<String>(
      'admin_send_inbox',
      params: <String, dynamic>{
        'p_user_id': userId,
        'p_subject': subject,
        'p_body': body,
      },
    );
    return id;
  }
}
