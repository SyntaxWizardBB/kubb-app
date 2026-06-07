import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/social/data/friend_models.dart';
import 'package:kubb_app/features/social/data/friend_repository.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart'
    show realtimeChannelProvider, realtimePollingFallbackProvider;
import 'package:kubb_domain/kubb_domain.dart';

/// Calling user's friend list (accepted + pending). Empty when the
/// session is signed out so the UI never blocks on the RPC for that
/// case.
final friendsListProvider =
    FutureProvider<List<FriendEntry>>((ref) async {
  final isAuthed = ref.watch(isAuthenticatedProvider);
  if (!isAuthed) return const <FriendEntry>[];
  return ref.read(friendRepositoryProvider).listForCaller();
});

/// Polling cadence used ONLY while the realtime fallback is active
/// (channel ≥60 s errored or kill-switch on). Authenticated concerns poll
/// at 30 s per ADR-0029 §(c) FC-6 — never the old 1 s discovery loop.
const Duration _friendsFallbackPollInterval = Duration(seconds: 30);

/// Friends CDC discovery (ADR-0029 §9 SRV-05 / §(e) C2-T2): replaces the old
/// 1 s `friendsPollingProvider`. A screen watches this provider while mounted
/// so the friends list flips from pending→accepted automatically once the
/// peer responds server-side — without any periodic poll.
///
/// friendships is stored canonically (PK low/high, CHECK low<high) and has no
/// single-column owner filter, so the CDC subscription rides the denormalised
/// `public.friend_edges` table (one owner-scoped row per direction, kept in
/// sync by a SECURITY DEFINER trigger; see migration 20261214000000). The
/// per-user channel is `friend_edges:owner_user_id=<uid>` over the app-wide
/// [realtimeChannelProvider] singleton (one WebSocket, multiplexed). On every
/// row-level change it invalidates [friendsListProvider] — exactly what the old
/// timer did, minus the timer. This provider emits no data; it only drives the
/// invalidation.
///
/// Fallback: when [realtimePollingFallbackProvider] reports the channel
/// unhealthy for this key, a single 30 s re-arming timer takes over. It is
/// gated strictly on that boolean — there is no unconditional `Timer.periodic`
/// for server-state discovery.
//
// Riverpod's autoDispose-provider type names are not part of the public
// API, so the lint stays suppressed.
// ignore: specify_nonobvious_property_types
final friendsCdcProvider = StreamProvider.autoDispose<void>((ref) {
  final userIdValue = ref.watch(currentUserIdProvider);
  if (userIdValue == null) {
    // Signed out — no subscription, no fallback poll.
    return const Stream<void>.empty();
  }
  final userId = UserId(userIdValue);
  final channelKey = friendsRealtimeChannelKey(userId);

  // CDC path: one row-level change → one list invalidation.
  final channel = ref.watch(realtimeChannelProvider);
  final cdcSub = channel
      .subscribe(
        table: 'friend_edges',
        filterColumn: 'owner_user_id',
        filterValue: userIdValue,
      )
      .listen((_) => ref.invalidate(friendsListProvider));

  // Fallback path: only poll while the gate says the channel is down.
  // A self-rearming one-shot Timer (NOT Timer.periodic — that is reserved for
  // the migrated-away pollers and barred by the FC-10(a) guard) gives the 30 s
  // cadence, cleanly stopped the moment the channel recovers.
  Timer? fallbackTimer;
  void armFallback() {
    fallbackTimer = Timer(_friendsFallbackPollInterval, () {
      ref.invalidate(friendsListProvider);
      armFallback();
    });
  }

  final fallbackSub = ref.listen<AsyncValue<bool>>(
    realtimePollingFallbackProvider(channelKey),
    (_, next) {
      final polling = next.maybeWhen(data: (v) => v, orElse: () => false);
      if (polling) {
        if (fallbackTimer == null) armFallback();
      } else {
        fallbackTimer?.cancel();
        fallbackTimer = null;
      }
    },
    fireImmediately: true,
  );

  ref.onDispose(() {
    fallbackTimer?.cancel();
    fallbackSub.close();
    unawaited(cdcSub.cancel());
    unawaited(channel.close(channelKey));
  });

  return const Stream<void>.empty();
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
