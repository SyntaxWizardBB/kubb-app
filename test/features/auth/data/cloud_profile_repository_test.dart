import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/auth/fake_cloud_profile_repository.dart';

void main() {
  late FakeCloudProfileRepository repo;

  setUp(() {
    repo = FakeCloudProfileRepository();
  });

  test('ensureProfile creates a row when missing', () async {
    final row = await repo.ensureProfile(
      userId: 'u1',
      nickname: 'lukas',
      avatarColor: '#FF8800',
    );

    expect(row.userId, 'u1');
    expect(row.nickname, 'lukas');
    expect(row.avatarColor, '#FF8800');
    expect(row.onboardingCompleted, isFalse);
  });

  test('ensureProfile is idempotent — second call returns the same row',
      () async {
    final first = await repo.ensureProfile(
      userId: 'u1',
      nickname: 'lukas',
      avatarColor: '#FF8800',
    );

    // Second call with different values — must not overwrite, but
    // should still succeed and return the original row.
    final second = await repo.ensureProfile(
      userId: 'u1',
      nickname: 'someone-else',
      avatarColor: '#000000',
    );

    expect(second.userId, first.userId);
    expect(second.nickname, 'lukas');
    expect(second.avatarColor, '#FF8800');
    expect(repo.storedUserIds.length, 1);
  });

  test('getProfile returns null when no row exists', () async {
    expect(await repo.getProfile(userId: 'never-stored'), isNull);
  });

  test('getProfile returns the stored row', () async {
    await repo.ensureProfile(userId: 'u1', nickname: 'lukas');
    final got = await repo.getProfile(userId: 'u1');
    expect(got!.nickname, 'lukas');
  });

  test('updateProfile patches only the supplied fields', () async {
    await repo.ensureProfile(
      userId: 'u1',
      nickname: 'lukas',
      avatarColor: '#FF8800',
    );

    final after = await repo.updateProfile(
      userId: 'u1',
      onboardingCompleted: true,
    );

    expect(after.nickname, 'lukas');
    expect(after.avatarColor, '#FF8800');
    expect(after.onboardingCompleted, isTrue);
  });

  test('updateProfile fails when no profile exists yet', () async {
    await expectLater(
      repo.updateProfile(userId: 'never-stored', nickname: 'x'),
      throwsA(isA<StateError>()),
    );
  });

  test('updateProfile can change nickname and avatarColor', () async {
    await repo.ensureProfile(
      userId: 'u1',
      nickname: 'lukas',
      avatarColor: '#FF8800',
    );

    final after = await repo.updateProfile(
      userId: 'u1',
      nickname: 'lukas-2',
      avatarColor: '#3366FF',
    );

    expect(after.nickname, 'lukas-2');
    expect(after.avatarColor, '#3366FF');
  });

  test('updateProfile recomputes nickname_hash when nickname changes',
      () async {
    // Existing keypair user — there is a backup row pinned to the
    // current nickname's hash.
    await repo.ensureProfile(userId: 'u1', nickname: 'lukas');
    repo.seedBackupHash(userId: 'u1', nickname: 'lukas');
    expect(repo.backupNicknameHashFor('u1'), 'lukas');

    // Rename the profile.
    await repo.updateProfile(userId: 'u1', nickname: 'lukas-2');

    // The keypair backup hash MUST move with the nickname — otherwise
    // the user is locked out of their own restore on a fresh device.
    expect(repo.backupNicknameHashFor('u1'), 'lukas-2');
  });

  test('updateProfile leaves nickname_hash alone for OAuth-only users',
      () async {
    // OAuth user — no keypair backup row exists, so no hash to track.
    await repo.ensureProfile(userId: 'u2', nickname: 'oauth-user');
    expect(repo.backupNicknameHashFor('u2'), isNull);

    await repo.updateProfile(userId: 'u2', nickname: 'oauth-user-renamed');

    // Still null — we did not invent a backup row.
    expect(repo.backupNicknameHashFor('u2'), isNull);
  });

  test('updateProfile leaves nickname_hash untouched on avatar-only update',
      () async {
    await repo.ensureProfile(userId: 'u1', nickname: 'lukas');
    repo.seedBackupHash(userId: 'u1', nickname: 'lukas');

    await repo.updateProfile(userId: 'u1', avatarColor: '#3366FF');

    expect(repo.backupNicknameHashFor('u1'), 'lukas');
  });
}
