import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';
import 'package:kubb_app/features/inbox/data/inbox_repository.dart';

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

/// Polling sentinel — a screen that `watch`es this keeps a Timer alive
/// that triggers a remote refresh every second, so an incoming friend
/// or match invite shows up without manual refresh. The refresh upserts
/// into the drift cache, which in turn drives the stream emission;
/// there is no provider invalidation involved.
// Riverpod's autoDispose-provider type names are not part of the
// public API, so the lint stays suppressed.
// ignore: specify_nonobvious_property_types
final inboxPollingProvider = Provider.autoDispose<void>((ref) {
  final timer = Timer.periodic(const Duration(seconds: 1), (_) {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    unawaited(
      ref.read(inboxRepositoryProvider).refreshFromRemote(userId).catchError(
            (Object _) => const <InboxMessage>[],
          ),
    );
  });
  ref.onDispose(timer.cancel);
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
