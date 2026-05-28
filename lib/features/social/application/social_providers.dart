import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/social/data/friend_models.dart';
import 'package:kubb_app/features/social/data/friend_repository.dart';

/// Calling user's friend list (accepted + pending). Empty when the
/// session is signed out so the UI never blocks on the RPC for that
/// case.
final friendsListProvider =
    FutureProvider<List<FriendEntry>>((ref) async {
  final isAuthed = ref.watch(isAuthenticatedProvider);
  if (!isAuthed) return const <FriendEntry>[];
  return ref.read(friendRepositoryProvider).listForCaller();
});

/// Polling sentinel — `ref.watch(friendsPollingProvider)` from a screen
/// keeps a Timer alive that invalidates [friendsListProvider] every
/// second. Lets the requester's UI flip from "wartet…" to
/// "Bereits Freund" without manual pull-to-refresh once the other side
/// has accepted server-side. Auto-disposes when the screen unmounts.
// Riverpod's autoDispose-provider type names are not part of the
// public API, so we suppress the lint here.
// ignore: specify_nonobvious_property_types
final friendsPollingProvider = Provider.autoDispose<void>((ref) {
  final timer = Timer.periodic(
    const Duration(seconds: 1),
    (_) => ref.invalidate(friendsListProvider),
  );
  ref.onDispose(timer.cancel);
});

/// `accepted` subset of [friendsListProvider].
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
}
