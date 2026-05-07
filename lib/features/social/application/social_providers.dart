import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/social/data/friend_models.dart';
import 'package:kubb_app/features/social/data/friend_repository.dart';
import 'package:kubb_app/features/social/data/group_models.dart';
import 'package:kubb_app/features/social/data/group_repository.dart';

/// Calling user's friend list (accepted + pending). Empty when the
/// session is signed out so the UI never blocks on the RPC for that
/// case.
final friendsListProvider =
    FutureProvider<List<FriendEntry>>((ref) async {
  final isAuthed = ref.watch(isAuthenticatedProvider);
  if (!isAuthed) return const <FriendEntry>[];
  return ref.read(friendRepositoryProvider).listForCaller();
});

/// `accepted` subset of [friendsListProvider]. Used by the group-invite
/// picker which only allows real friends.
final acceptedFriendsProvider = Provider<List<FriendEntry>>((ref) {
  return ref.watch(friendsListProvider).maybeWhen(
        data: (entries) =>
            entries.where((e) => e.isAccepted).toList(growable: false),
        orElse: () => const <FriendEntry>[],
      );
});

/// One-shot search result. Family parameter = lower-cased query string.
// Riverpod's family-provider type names are not part of the public API,
// so we suppress the lint here and rely on the generic args for inference.
// ignore: specify_nonobvious_property_types
final friendSearchProvider =
    FutureProvider.family<List<FriendCandidate>, String>((ref, query) async {
  if (query.length < 2) return const <FriendCandidate>[];
  return ref.read(friendRepositoryProvider).searchByUsername(query);
});

final groupsListProvider =
    FutureProvider<List<GroupListEntry>>((ref) async {
  final isAuthed = ref.watch(isAuthenticatedProvider);
  if (!isAuthed) return const <GroupListEntry>[];
  return ref.read(groupRepositoryProvider).listForCaller();
});

// Riverpod's family-provider type names are not part of the public API,
// so we suppress the lint here and rely on the generic args for inference.
// ignore: specify_nonobvious_property_types
final groupMembersProvider =
    FutureProvider.family<List<GroupMember>, String>((ref, groupId) async {
  return ref.read(groupRepositoryProvider).membersFor(groupId);
});

/// Imperative action surface so screen widgets do not need to repeat
/// invalidate-after-write boilerplate at every call site.
final socialActionsProvider = Provider<SocialActions>((ref) {
  return SocialActions(ref);
});

class SocialActions {
  SocialActions(this._ref);
  final Ref _ref;

  Future<void> sendFriendRequest(String userId) async {
    await _ref.read(friendRepositoryProvider).sendRequest(userId);
    _ref.invalidate(friendsListProvider);
  }

  Future<void> acceptFriendRequest(String userId) async {
    await _ref.read(friendRepositoryProvider).acceptRequest(userId);
    _ref.invalidate(friendsListProvider);
  }

  Future<void> rejectFriendRequest(String userId) async {
    await _ref.read(friendRepositoryProvider).rejectRequest(userId);
    _ref.invalidate(friendsListProvider);
  }

  Future<void> removeFriend(String userId) async {
    await _ref.read(friendRepositoryProvider).remove(userId);
    _ref.invalidate(friendsListProvider);
  }

  Future<String> createGroup(String name) async {
    try {
      final id = await _ref.read(groupRepositoryProvider).create(name);
      _ref.invalidate(groupsListProvider);
      return id;
    } on Object catch (e, st) {
      // Surface the underlying error in adb logcat — the create-dialog
      // shows a snackbar but only with toString(); the stack trace and
      // any wrapped PostgrestException details land here.
      // ignore: avoid_print
      print('createGroup failed for "$name": $e\n$st');
      rethrow;
    }
  }

  Future<void> renameGroup(String groupId, String name) async {
    await _ref.read(groupRepositoryProvider).rename(groupId, name);
    _ref.invalidate(groupsListProvider);
  }

  Future<void> deleteGroup(String groupId) async {
    await _ref.read(groupRepositoryProvider).delete(groupId);
    _ref
      ..invalidate(groupsListProvider)
      ..invalidate(groupMembersProvider(groupId));
  }

  Future<void> inviteMember(String groupId, String userId) async {
    await _ref.read(groupRepositoryProvider).inviteMember(groupId, userId);
    _ref
      ..invalidate(groupMembersProvider(groupId))
      ..invalidate(groupsListProvider);
  }

  Future<void> removeMember(String groupId, String userId) async {
    await _ref.read(groupRepositoryProvider).removeMember(groupId, userId);
    _ref
      ..invalidate(groupMembersProvider(groupId))
      ..invalidate(groupsListProvider);
  }
}
