import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/features/inbox/data/dao/inbox_messages_dao.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read/write access to `public.user_inbox_messages` for the
/// currently authenticated user. RLS scopes every query to
/// `user_id = auth.uid()`, so the client never needs to thread
/// the user_id through the calls itself.
///
/// Offline behaviour (ADR-0012, bug-hunt R20-F-03): the repository
/// keeps a drift-backed mirror of the user's non-archived messages so
/// that the screen can hydrate on app open without a network call.
/// [watchForUser] reads from that mirror; [refreshFromRemote] pulls a
/// fresh snapshot from Supabase and upserts the result back into the
/// mirror. Mutating ops ([markRead], [archive], [reply]) write through
/// to the cache after the server roundtrip so a follow-up open without
/// network still reflects the user's last action.
class InboxRepository {
  InboxRepository({
    required SupabaseClient client,
    required InboxMessagesDao dao,
  })  : _client = client,
        _dao = dao;

  final SupabaseClient _client;
  final InboxMessagesDao _dao;

  /// All non-archived messages, newest first.
  Future<List<InboxMessage>> list() async {
    final rows = await _client
        .from('user_inbox_messages')
        .select()
        .filter('archived_at', 'is', null)
        .order('sent_at', ascending: false);
    return rows.map(InboxMessage.fromRow).toList();
  }

  /// All archived messages, newest first. Read straight from Supabase — the
  /// local drift mirror only caches the active inbox (archiving drops the row
  /// locally), so the archive view always reflects the server. The owner-read
  /// RLS policy already scopes this to `user_id = auth.uid()`.
  Future<List<InboxMessage>> listArchived() async {
    final rows = await _client
        .from('user_inbox_messages')
        .select()
        .not('archived_at', 'is', null)
        .order('archived_at', ascending: false);
    return rows.map(InboxMessage.fromRow).toList();
  }

  /// Permanently deletes the caller's archived messages. Server-side this is a
  /// hard delete via the `inbox_purge_archived` SECURITY DEFINER RPC (the table
  /// has no DELETE RLS policy); it removes only `archived_at IS NOT NULL` rows,
  /// so still-needed records like tournament registrations (separate tables)
  /// are untouched. The local drift mirror only holds the active inbox, so
  /// there is nothing to clear locally — the active inbox stays intact.
  /// Returns the number of server rows removed.
  Future<int> purgeArchived() async {
    return _client.rpc<int>('inbox_purge_archived');
  }

  /// Live view backed by the local drift cache. The first emission
  /// comes from disk (zero network roundtrip), so the inbox screen can
  /// paint immediately after app launch — even when offline. Callers
  /// should invoke [refreshFromRemote] separately to top the cache up
  /// from Supabase; subsequent upserts cause the stream to re-emit.
  Stream<List<InboxMessage>> watchForUser(String userId) {
    return _dao
        .watchByUser(userId)
        .map((rows) => rows.map(_inboxMessageFromCache).toList());
  }

  /// One-shot read from the local drift cache. Useful for tests and
  /// for code paths that need a snapshot without keeping a stream
  /// subscription open.
  Future<List<InboxMessage>> loadFromCache(String userId) async {
    final rows = await _dao.listByUser(userId);
    return rows.map(_inboxMessageFromCache).toList();
  }

  /// Pulls the user's non-archived messages from Supabase and upserts
  /// each one into the local drift cache. Returns the freshly fetched
  /// list so callers that already have an awaiter can react to it.
  ///
  /// Failures are intentionally re-thrown — the caller (controller /
  /// stream subscriber) decides whether to surface them as a snack or
  /// to silently fall back on the cached state.
  Future<List<InboxMessage>> refreshFromRemote(String userId) async {
    final messages = await list();
    await _dao.upsertMany(
      messages
          .map((m) => _cacheCompanionFromMessage(userId, m))
          .toList(growable: false),
    );
    return messages;
  }

  /// Stamps `read_at` on a message that the user has opened. No-op if
  /// the row is already read; relies on the RLS UPDATE policy to scope
  /// the write to the message's owner. Also stamps the local mirror
  /// so an offline reopen doesn't show the unread dot again.
  Future<void> markRead(String id) async {
    await _client
        .from('user_inbox_messages')
        .update(<String, dynamic>{
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .filter('read_at', 'is', null);
    await _stampLocalTimestamp(id, readAt: DateTime.now().toUtc());
  }

  /// Archives a message — the row stays in the database but is
  /// excluded from [list]. Reserves the option to surface archived
  /// messages later in a "trash" view without a destructive delete.
  /// The local mirror drops the row entirely so the stream stops
  /// emitting it without a Supabase roundtrip.
  Future<void> archive(String id) async {
    await _client
        .from('user_inbox_messages')
        .update(<String, dynamic>{
          'archived_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
    await _dao.deleteById(id);
  }

  /// Archives every non-archived message of the caller in one shot. The
  /// owner-update RLS policy scopes the write to `user_id = auth.uid()`, and
  /// the `archived_at IS NULL` filter keeps already-archived rows untouched.
  /// The local mirror (active inbox only) is cleared afterwards so the inbox
  /// empties immediately without a Supabase roundtrip.
  Future<void> archiveAll(String userId) async {
    await _client
        .from('user_inbox_messages')
        .update(<String, dynamic>{
          'archived_at': DateTime.now().toUtc().toIso8601String(),
        })
        .filter('archived_at', 'is', null);
    await _dao.deleteForUser(userId);
  }

  /// User's response to a `verification_request` message. The reply
  /// payload is application-defined; today the admin-side query just
  /// reads it back as JSON.
  Future<void> reply(String id, Map<String, dynamic> payload) async {
    await _client.from('user_inbox_messages').update(<String, dynamic>{
      'replied_at': DateTime.now().toUtc().toIso8601String(),
      'reply_payload': payload,
    }).eq('id', id);
    await _stampLocalTimestamp(id, repliedAt: DateTime.now().toUtc());
  }

  Future<void> _stampLocalTimestamp(
    String id, {
    DateTime? readAt,
    DateTime? repliedAt,
  }) async {
    await _dao.stampTimestamps(
      id,
      readAt: readAt,
      repliedAt: repliedAt,
    );
  }

  static InboxMessage _inboxMessageFromCache(CachedInboxMessage row) {
    final body = jsonDecode(row.bodyJson) as Map<String, dynamic>;
    DateTime? fromMs(int? ms) =>
        ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    // The cached wire kind alone is ambiguous for shoot-outs (wire kind is
    // 'tournament_round'); fromWire needs the action_payload to disambiguate
    // 'shootout' from a plain tournament round. Pass it through exactly like
    // InboxMessage.fromRow, otherwise the offline-first cache path mis-routes
    // the shoot-out message to `notice` and the CTA never renders.
    final actionPayload =
        (body['action_payload'] as Map?)?.cast<String, dynamic>();
    return InboxMessage(
      id: row.id,
      kind: InboxMessageKind.fromWire(row.kind, actionPayload: actionPayload),
      subject: body['subject'] as String? ?? '',
      body: body['body'] as String? ?? '',
      sentAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true),
      readAt: fromMs(row.readAt),
      repliedAt: fromMs(row.repliedAt),
      archivedAt: body['archived_at'] is String
          ? DateTime.parse(body['archived_at'] as String)
          : null,
      actionPayload: actionPayload,
      replyPayload: (body['reply_payload'] as Map?)?.cast<String, dynamic>(),
    );
  }

  static InboxMessagesCompanion _cacheCompanionFromMessage(
    String userId,
    InboxMessage m,
  ) {
    final bodyJson = jsonEncode(<String, dynamic>{
      'subject': m.subject,
      'body': m.body,
      if (m.archivedAt != null)
        'archived_at': m.archivedAt!.toUtc().toIso8601String(),
      if (m.actionPayload != null) 'action_payload': m.actionPayload,
      if (m.replyPayload != null) 'reply_payload': m.replyPayload,
    });
    return InboxMessagesCompanion(
      id: Value(m.id),
      userId: Value(userId),
      kind: Value(_kindToWire(m.kind)),
      bodyJson: Value(bodyJson),
      createdAt: Value(m.sentAt.toUtc().millisecondsSinceEpoch),
      readAt: Value(m.readAt?.toUtc().millisecondsSinceEpoch),
      repliedAt: Value(m.repliedAt?.toUtc().millisecondsSinceEpoch),
    );
  }

  static String _kindToWire(InboxMessageKind kind) {
    switch (kind) {
      case InboxMessageKind.notice:
        return 'notice';
      case InboxMessageKind.verificationRequest:
        return 'verification_request';
      case InboxMessageKind.system:
        return 'system';
      case InboxMessageKind.teamInvitation:
        return 'team_invitation';
      case InboxMessageKind.teamMemberRemoved:
        return 'team_member_removed';
      case InboxMessageKind.teamDissolved:
        return 'team_dissolved';
      case InboxMessageKind.clubInvitation:
        return 'club_invitation';
      case InboxMessageKind.clubMemberRemoved:
        return 'club_member_removed';
      case InboxMessageKind.clubJoinRequest:
        return 'club_join_request';
      case InboxMessageKind.tournamentShootout:
        // Server-side wire kind for the shoot-out task is the generic
        // 'tournament_round'; the shoot-out is disambiguated by the
        // action_payload, not a distinct wire kind (P6 D2a).
        return 'tournament_round';
      case InboxMessageKind.tournamentFinished:
        return 'tournament_finished';
    }
  }
}

final inboxMessagesDaoProvider = Provider<InboxMessagesDao>((ref) {
  return ref.watch(appDatabaseProvider).inboxMessagesDao;
});

final inboxRepositoryProvider = Provider<InboxRepository>((ref) {
  return InboxRepository(
    client: Supabase.instance.client,
    dao: ref.watch(inboxMessagesDaoProvider),
  );
});
