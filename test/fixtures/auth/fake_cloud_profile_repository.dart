import 'package:kubb_app/features/auth/data/cloud_profile_repository.dart';

class FakeCloudProfileRepository implements CloudProfileRepository {
  final Map<String, CloudProfile> _rows = <String, CloudProfile>{};

  /// Mirrors the server-side `user_keypair_backups.nickname_hash` for
  /// each user_id. updateProfile keeps this in sync when the nickname
  /// changes — the same atomic guarantee the real RPC enforces. Tests
  /// can read this to assert the hash actually moved.
  ///
  /// Real value is opaque (sha256(nick || salt) on the server). For
  /// tests we just store the nickname itself as the "hash" — what
  /// matters is that it changes when the nick changes.
  final Map<String, String> _backupNicknameHashes = <String, String>{};

  int ensureCount = 0;
  int updateCount = 0;

  Iterable<String> get storedUserIds => _rows.keys;

  String? backupNicknameHashFor(String userId) =>
      _backupNicknameHashes[userId];

  /// Seeds a tracked hash so tests can simulate a pre-existing keypair
  /// backup without going through ensureProfile.
  void seedBackupHash({required String userId, required String nickname}) {
    _backupNicknameHashes[userId] = nickname;
  }

  @override
  Future<CloudProfile> ensureProfile({
    required String userId,
    required String nickname,
    String? avatarColor,
  }) async {
    ensureCount += 1;
    final existing = _rows[userId];
    if (existing != null) return existing;
    final row = CloudProfile(
      userId: userId,
      nickname: nickname,
      avatarColor: avatarColor,
    );
    _rows[userId] = row;
    return row;
  }

  @override
  Future<CloudProfile?> getProfile({required String userId}) async {
    return _rows[userId];
  }

  @override
  Future<CloudProfile> updateProfile({
    required String userId,
    String? nickname,
    String? avatarColor,
    bool? onboardingCompleted,
  }) async {
    updateCount += 1;
    final existing = _rows[userId];
    if (existing == null) {
      throw StateError('updateProfile called before ensureProfile');
    }
    final next = CloudProfile(
      userId: userId,
      nickname: nickname ?? existing.nickname,
      avatarColor: avatarColor ?? existing.avatarColor,
      onboardingCompleted:
          onboardingCompleted ?? existing.onboardingCompleted,
    );
    _rows[userId] = next;

    // Mirror the RPC: a nickname change recomputes the keypair-backup
    // hash in the same transaction. Only touched if a backup hash is
    // tracked for this user (matches the real "no-op when no keypair
    // backup row exists" behaviour).
    if (nickname != null && _backupNicknameHashes.containsKey(userId)) {
      _backupNicknameHashes[userId] = nickname;
    }
    return next;
  }
}
