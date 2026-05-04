import 'package:kubb_app/features/auth/data/cloud_profile_repository.dart';

class FakeCloudProfileRepository implements CloudProfileRepository {
  final Map<String, CloudProfile> _rows = <String, CloudProfile>{};

  int ensureCount = 0;
  int updateCount = 0;

  Iterable<String> get storedUserIds => _rows.keys;

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
    return next;
  }
}
