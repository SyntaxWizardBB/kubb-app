import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read/write access to `public.user_inbox_messages` for the
/// currently authenticated user. RLS scopes every query to
/// `user_id = auth.uid()`, so the client never needs to thread
/// the user_id through the calls itself.
class InboxRepository {
  InboxRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  /// All non-archived messages, newest first.
  Future<List<InboxMessage>> list() async {
    final rows = await _client
        .from('user_inbox_messages')
        .select()
        .filter('archived_at', 'is', null)
        .order('sent_at', ascending: false);
    return rows.map(InboxMessage.fromRow).toList();
  }

  /// Stamps `read_at` on a message that the user has opened. No-op if
  /// the row is already read; relies on the RLS UPDATE policy to scope
  /// the write to the message's owner.
  Future<void> markRead(String id) async {
    await _client
        .from('user_inbox_messages')
        .update(<String, dynamic>{
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .filter('read_at', 'is', null);
  }

  /// Archives a message — the row stays in the database but is
  /// excluded from [list]. Reserves the option to surface archived
  /// messages later in a "trash" view without a destructive delete.
  Future<void> archive(String id) async {
    await _client
        .from('user_inbox_messages')
        .update(<String, dynamic>{
          'archived_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }

  /// User's response to a `verification_request` message. The reply
  /// payload is application-defined; today the admin-side query just
  /// reads it back as JSON.
  Future<void> reply(String id, Map<String, dynamic> payload) async {
    await _client.from('user_inbox_messages').update(<String, dynamic>{
      'replied_at': DateTime.now().toUtc().toIso8601String(),
      'reply_payload': payload,
    }).eq('id', id);
  }
}

final inboxRepositoryProvider = Provider<InboxRepository>((ref) {
  return InboxRepository(client: Supabase.instance.client);
});
