import 'package:kubb_domain/kubb_domain.dart';

/// Raised when a profile rename/create is rejected because another user
/// already owns the chosen nickname (server SQLSTATE 23505 on the citext
/// UNIQUE constraint). Lets the UI render a friendly "name taken" message
/// even if the optimistic live availability check raced.
class DuplicateNicknameException implements Exception {
  const DuplicateNicknameException();
  @override
  String toString() => 'DuplicateNicknameException';
}

/// Snapshot of the cloud-side `user_profiles` row.
class CloudProfile {
  const CloudProfile({
    required this.userId,
    required this.nickname,
    this.avatarColor,
    this.onboardingCompleted = false,
    this.visibility = ProfileVisibility.friendsOnly,
    this.isOrganizer = true,
  });

  final String userId;
  final String nickname;
  final String? avatarColor;
  final bool onboardingCompleted;

  /// Visibility tier for the profile row — drives the RLS read policy
  /// server-side and the picker on the Settings screen. Defaults to
  /// [ProfileVisibility.friendsOnly] (Privacy-by-Default per DSGVO
  /// Art. 25).
  final ProfileVisibility visibility;

  /// Whether the user may create/publish tournaments (coarse organizer
  /// role, P1 Tournament-Hub). Defaults to `true` so every account is an
  /// organizer for now; a later verification flow (Roadmap B10) can flip
  /// the server-side default. Drives the "create tournament" tile on the
  /// tournament hub and is enforced server-side in `tournament_create`.
  final bool isOrganizer;

  CloudProfile copyWith({
    String? userId,
    String? nickname,
    String? avatarColor,
    bool? onboardingCompleted,
    ProfileVisibility? visibility,
    bool? isOrganizer,
  }) {
    return CloudProfile(
      userId: userId ?? this.userId,
      nickname: nickname ?? this.nickname,
      avatarColor: avatarColor ?? this.avatarColor,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      visibility: visibility ?? this.visibility,
      isOrganizer: isOrganizer ?? this.isOrganizer,
    );
  }
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

  /// Whether [nickname] is free to use. Case- and whitespace-insensitive;
  /// excludes the caller's own current nickname server-side so re-saving an
  /// unchanged name is allowed. Returns false for blank input.
  Future<bool> isNicknameAvailable(String nickname);

  /// Patches the row with whatever non-null fields are passed in.
  /// Returns the post-update row.
  Future<CloudProfile> updateProfile({
    required String userId,
    String? nickname,
    String? avatarColor,
    bool? onboardingCompleted,
    ProfileVisibility? visibility,
  });
}
