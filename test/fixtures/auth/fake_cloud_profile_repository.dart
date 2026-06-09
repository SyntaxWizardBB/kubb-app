import 'package:kubb_app/features/auth/data/cloud_profile_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

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

  /// Nicknames (lower-cased) that the fake reports as already taken by some
  /// OTHER user. Tests add to this to drive the "name taken" block.
  final Set<String> takenNicknames = <String>{};

  Iterable<String> get storedUserIds => _rows.keys;

  @override
  Future<bool> isNicknameAvailable(String nickname) async {
    final norm = nickname.trim().toLowerCase();
    if (norm.isEmpty) return false;
    return !takenNicknames.contains(norm);
  }

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
    ProfileVisibility? visibility,
  }) async {
    updateCount += 1;
    final existing = _rows[userId];
    if (existing == null) {
      throw StateError('updateProfile called before ensureProfile');
    }
    // Mirror the server citext UNIQUE: a rename onto another user's name is
    // rejected with the typed duplicate exception.
    if (nickname != null &&
        takenNicknames.contains(nickname.trim().toLowerCase())) {
      throw const DuplicateNicknameException();
    }
    final next = CloudProfile(
      userId: userId,
      nickname: nickname ?? existing.nickname,
      avatarColor: avatarColor ?? existing.avatarColor,
      onboardingCompleted:
          onboardingCompleted ?? existing.onboardingCompleted,
      visibility: visibility ?? existing.visibility,
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
