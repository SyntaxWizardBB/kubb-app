import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';
import 'package:kubb_app/features/inbox/data/inbox_repository.dart';

/// Stream of the current user's inbox. Recomputes whenever the auth
/// session flips so a sign-out followed by a different user signing
/// in doesn't show stale messages.
final inboxMessagesProvider = FutureProvider<List<InboxMessage>>((ref) async {
  final isAuthed = ref.watch(isAuthenticatedProvider);
  if (!isAuthed) return const <InboxMessage>[];
  return ref.read(inboxRepositoryProvider).list();
});

/// Polling sentinel — a screen that `watch`es this keeps a Timer alive
/// that invalidates [inboxMessagesProvider] every 8 seconds, so an
/// incoming friend or match invite shows up without manual refresh.
/// Same shape as the friends- and match-detail polling providers.
// Riverpod's autoDispose-provider type names are not part of the
// public API, so the lint stays suppressed.
// ignore: specify_nonobvious_property_types
final inboxPollingProvider = Provider.autoDispose<void>((ref) {
  final timer = Timer.periodic(
    const Duration(seconds: 8),
    (_) => ref.invalidate(inboxMessagesProvider),
  );
  ref.onDispose(timer.cancel);
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
/// re-implementing the FutureProvider invalidation pattern at every
/// callsite.
final inboxActionsProvider = Provider<InboxActions>((ref) {
  return InboxActions(ref);
});

class InboxActions {
  InboxActions(this._ref);
  final Ref _ref;

  Future<void> markRead(String id) async {
    await _ref.read(inboxRepositoryProvider).markRead(id);
    _ref.invalidate(inboxMessagesProvider);
  }

  Future<void> reply(String id, Map<String, dynamic> payload) async {
    await _ref.read(inboxRepositoryProvider).reply(id, payload);
    _ref.invalidate(inboxMessagesProvider);
  }

  Future<void> archive(String id) async {
    await _ref.read(inboxRepositoryProvider).archive(id);
    _ref.invalidate(inboxMessagesProvider);
  }
}
