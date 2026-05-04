import 'package:kubb_app/features/auth/data/cloud_profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CloudProfileRepositoryImpl implements CloudProfileRepository {
  CloudProfileRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  Future<CloudProfile> ensureProfile({
    required String userId,
    required String nickname,
    String? avatarColor,
  }) async {
    // ON CONFLICT DO NOTHING then SELECT — Postgres returns the
    // existing row for an existing user_id and the inserted row
    // otherwise.
    await _client.from('user_profiles').upsert(<String, dynamic>{
      'user_id': userId,
      'nickname': nickname,
      'avatar_color': avatarColor,
    }, ignoreDuplicates: true);

    final row = await getProfile(userId: userId);
    if (row == null) {
      throw StateError('ensureProfile produced no row — server bug');
    }
    return row;
  }

  @override
  Future<CloudProfile?> getProfile({required String userId}) async {
    final rows = await _client
        .from('user_profiles')
        .select('user_id, nickname, avatar_color, onboarding_completed')
        .eq('user_id', userId)
        .limit(1);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  @override
  Future<CloudProfile> updateProfile({
    required String userId,
    String? nickname,
    String? avatarColor,
    bool? onboardingCompleted,
  }) async {
    // Routed through fn_profile_update_with_hash so a nickname change
    // recomputes user_keypair_backups.nickname_hash atomically. A plain
    // UPDATE on user_profiles would leave the hash stale and lock the
    // user out on a fresh install.
    final response = await _client.rpc<Map<String, dynamic>>(
      'fn_profile_update_with_hash',
      params: <String, dynamic>{
        'p_nickname': nickname,
        'p_avatar_color': avatarColor,
        'p_onboarding_done': onboardingCompleted,
      },
    );
    return _fromRow(response);
  }

  CloudProfile _fromRow(Map<String, dynamic> row) {
    return CloudProfile(
      userId: row['user_id'] as String,
      nickname: row['nickname'] as String,
      avatarColor: row['avatar_color'] as String?,
      onboardingCompleted:
          (row['onboarding_completed'] as bool?) ?? false,
    );
  }
}
