/// Snapshot of the cloud-side `user_profiles` row.
class CloudProfile {
  const CloudProfile({
    required this.userId,
    required this.nickname,
    this.avatarColor,
    this.onboardingCompleted = false,
  });

  final String userId;
  final String nickname;
  final String? avatarColor;
  final bool onboardingCompleted;
}

/// Read / upsert / patch the current user's `user_profiles` row.
///
/// Inserts use `ON CONFLICT (user_id) DO NOTHING RETURNING *` semantics
/// (server-side) so calling [ensureProfile] twice for the same user
/// produces only one row.
abstract class CloudProfileRepository {
  /// Creates the profile row for [userId] if missing, returns the
  /// (existing or newly-created) row either way. Idempotent.
  Future<CloudProfile> ensureProfile({
    required String userId,
    required String nickname,
    String? avatarColor,
  });

  /// Reads the current row for [userId], or null if no row exists yet.
  Future<CloudProfile?> getProfile({required String userId});

  /// Patches the row with whatever non-null fields are passed in.
  /// Returns the post-update row.
  Future<CloudProfile> updateProfile({
    required String userId,
    String? nickname,
    String? avatarColor,
    bool? onboardingCompleted,
  });
}
