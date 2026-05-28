import 'package:drift/drift.dart';

/// Local cache of `public.user_inbox_messages` rows for the currently
/// signed-in user.
///
/// ADR-0012 designates the inbox as load-bearing for the social and
/// match-consensus flows. The bug-hunt entry R20-F-03 surfaced that
/// after an app kill without network, the screen could not render
/// previously-seen items because nothing was persisted locally. This
/// table is the hydrate-on-open store the repository reads from before
/// it issues a Supabase refresh.
///
/// The row schema is intentionally narrow: identity, ownership, kind
/// and timestamps live in their own columns so DAO queries can filter
/// and order without parsing JSON. Anything else the UI may need
/// (subject, body, action and reply payloads, archive timestamp) is
/// serialised into [bodyJson] — the wire shape is owned by the
/// repository's JSON encoder, not by drift.
///
/// The drift row data class is named `CachedInboxMessage` (not
/// `InboxMessage`) so it does not collide with the domain model in
/// `lib/features/inbox/data/inbox_message.dart`. The repository
/// converts between the two.
@DataClassName('CachedInboxMessage')
class InboxMessages extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get kind => text()();
  TextColumn get bodyJson => text()();

  /// Epoch milliseconds (UTC) for the original server `sent_at`.
  /// Stored as `int` to keep the row trivially comparable across
  /// platforms without leaning on drift's `DateTime` encoding rules.
  IntColumn get createdAt => integer()();

  /// Epoch milliseconds (UTC); nullable mirror of the server column.
  IntColumn get readAt => integer().nullable()();

  /// Epoch milliseconds (UTC); nullable mirror of the server column.
  IntColumn get repliedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
