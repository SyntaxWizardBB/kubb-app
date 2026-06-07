import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';
import 'package:kubb_app/features/inbox/data/inbox_repository.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart'
    show realtimeChannelProvider, realtimePollingFallbackProvider;
import 'package:kubb_domain/kubb_domain.dart';

/// Stream of the current user's inbox. Backed by the drift cache so
/// the first frame after app open can render without a network call
/// (ADR-0012 / bug-hunt R20-F-03). On subscription the provider also
/// kicks off a Supabase refresh in the background; the result is
/// upserted into the cache and the stream re-emits automatically.
final inboxMessagesProvider = StreamProvider<List<InboxMessage>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return Stream<List<InboxMessage>>.value(const <InboxMessage>[]);
  }
  final repo = ref.read(inboxRepositoryProvider);
  // Fire-and-forget. The stream below will emit the refreshed payload
  // once the upsert into the drift cache lands; if the network call
  // fails (offline at the pitch) the subscriber still sees the cached
  // snapshot from disk.
  unawaited(
    repo.refreshFromRemote(userId).catchError(
          (Object _) => const <InboxMessage>[],
        ),
  );
  return repo.watchForUser(userId);
});

/// Polling cadence used ONLY while the realtime fallback is active
/// (channel ≥60 s errored or kill-switch on). Authenticated concerns poll
/// at 30 s per ADR-0029 §(c) FC-6 — never the old 1 s discovery loop.
const Duration _inboxFallbackPollInterval = Duration(seconds: 30);

/// Inbox CDC discovery (ADR-0029 §(d) SRV-01 / §(e) C1-T1): the durable
/// notification-spine subscription. Opened once on the app shell so it
/// lives across navigation and keeps the bell badge current.
///
/// Subscribes to the single per-user CDC channel
/// `user_inbox_messages:user_id=<uid>` over the app-wide
/// [realtimeChannelProvider] singleton (one WebSocket, multiplexed). On
/// every row-level change it fires a background
/// [InboxRepository.refreshFromRemote] — exactly what the old 1 s timer
/// did, minus the timer — which upserts into the drift cache and re-emits
/// [inboxMessagesProvider]/[inboxUnreadCountProvider]. Those providers stay
/// the unchanged data source for UI and badge; this provider emits no data,
/// it only drives the refresh.
///
/// Fallback: when [realtimePollingFallbackProvider] reports the channel
/// unhealthy for this key, a single 30 s refresh timer takes over. It is
/// gated strictly on that boolean — there is no unconditional
/// `Timer.periodic` for server-state discovery.
//
// Riverpod's autoDispose-provider type names are not part of the public
// API, so the lint stays suppressed.
// ignore: specify_nonobvious_property_types
final inboxCdcProvider = StreamProvider.autoDispose<void>((ref) {
  final userIdValue = ref.watch(currentUserIdProvider);
  if (userIdValue == null) {
    // Signed out — no subscription, no fallback poll.
    return const Stream<void>.empty();
  }
  final userId = UserId(userIdValue);
  final channelKey = inboxRealtimeChannelKey(userId);

  void refresh() {
    unawaited(
      ref.read(inboxRepositoryProvider).refreshFromRemote(userIdValue).catchError(
            (Object _) => const <InboxMessage>[],
          ),
    );
  }

  // CDC path: one row-level change → one background refresh.
  final channel = ref.watch(realtimeChannelProvider);
  final cdcSub = channel
      .subscribe(
        table: 'user_inbox_messages',
        filterColumn: 'user_id',
        filterValue: userIdValue,
      )
      .listen((_) => refresh());

  // Fallback path: only poll while the gate says the channel is down.
  // A self-rearming one-shot Timer (NOT Timer.periodic — that is reserved
  // for the migrated-away pollers and barred by the FC-10(a) guard) gives
  // the 30 s cadence, cleanly stopped the moment the channel recovers.
  Timer? fallbackTimer;
  void armFallback() {
    fallbackTimer = Timer(_inboxFallbackPollInterval, () {
      refresh();
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

/// The caller's archived messages, newest first. Read straight from the
/// server (the drift mirror only caches the active inbox), so the archive
/// view always reflects the canonical state. Invalidated after a purge.
final archivedInboxProvider = FutureProvider<List<InboxMessage>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const <InboxMessage>[];
  return ref.read(inboxRepositoryProvider).listArchived();
});

/// Count of unread (non-archived) messages. Cheap derivation off
/// [inboxMessagesProvider] so a badge in the app shell doesn't need
/// its own query.
final inboxUnreadCountProvider = Provider<int>((ref) {
  return ref.watch(inboxMessagesProvider).maybeWhen(
        data: (msgs) => msgs.where((m) => m.isUnread).length,
        orElse: () => 0,
      );
});

/// Imperative action surface for the inbox screen. Reads fall back to
/// [inboxMessagesProvider]; this notifier exists for the writes
/// (mark-read / reply / archive) so the screen can dispatch without
/// re-implementing the stream-refresh pattern at every callsite.
final inboxActionsProvider = Provider<InboxActions>((ref) {
  return InboxActions(ref);
});

class InboxActions {
  InboxActions(this._ref);
  final Ref _ref;

  Future<void> markRead(String id) async {
    await _ref.read(inboxRepositoryProvider).markRead(id);
  }

  Future<void> reply(String id, Map<String, dynamic> payload) async {
    await _ref.read(inboxRepositoryProvider).reply(id, payload);
  }

  Future<void> archive(String id) async {
    await _ref.read(inboxRepositoryProvider).archive(id);
  }

  /// Archives every message in the active inbox at once. No-op when signed
  /// out. Refreshes the archive view so the moved messages show up there.
  Future<void> archiveAll() async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;
    await _ref.read(inboxRepositoryProvider).archiveAll(userId);
    _ref.invalidate(archivedInboxProvider);
  }

  /// Permanently deletes all archived messages (server hard-delete; local
  /// active inbox untouched). Refreshes the archive view afterwards.
  Future<int> purgeArchived() async {
    final deleted = await _ref.read(inboxRepositoryProvider).purgeArchived();
    _ref.invalidate(archivedInboxProvider);
    return deleted;
  }
}
