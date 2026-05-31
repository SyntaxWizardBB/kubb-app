/// Categorisation of an inbox message — drives how the UI renders it.
/// Mirrors the `kind` CHECK constraint on `public.user_inbox_messages`.
enum InboxMessageKind {
  /// Read-only banner from the operator (release notes, hints).
  notice,

  /// Operator asks the user to confirm / deny something. Renders an
  /// inline action panel; the user's answer goes back through the
  /// reply_payload column.
  verificationRequest,

  /// Automated system event (account state change, security alert).
  system,

  /// Team-flow notifications (M3.1). All three are first-class kinds on
  /// `public.user_inbox_messages` and routed by team RPCs (T4/T5) — the
  /// client renders them via dedicated UI in T14, not the generic
  /// `verification_request` fallback.
  teamInvitation,
  teamMemberRemoved,
  teamDissolved,

  /// Club-flow notifications (P5): an invitation to join a Verein (routed to
  /// an accept/decline dialog), a removal notice, and a join request that
  /// managers act on from the club detail screen.
  clubInvitation,
  clubMemberRemoved,
  clubJoinRequest;

  static InboxMessageKind fromWire(String raw) {
    switch (raw) {
      case 'notice':
        return InboxMessageKind.notice;
      case 'verification_request':
        return InboxMessageKind.verificationRequest;
      case 'system':
        return InboxMessageKind.system;
      case 'team_invitation':
        return InboxMessageKind.teamInvitation;
      case 'team_member_removed':
        return InboxMessageKind.teamMemberRemoved;
      case 'team_dissolved':
        return InboxMessageKind.teamDissolved;
      case 'club_invitation':
        return InboxMessageKind.clubInvitation;
      case 'club_member_removed':
        return InboxMessageKind.clubMemberRemoved;
      case 'club_join_request':
        return InboxMessageKind.clubJoinRequest;
      default:
        return InboxMessageKind.notice;
    }
  }
}

/// One row of `public.user_inbox_messages`. Immutable, plain Dart;
/// belongs to the data layer.
class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.kind,
    required this.subject,
    required this.body,
    required this.sentAt,
    this.readAt,
    this.repliedAt,
    this.archivedAt,
    this.actionPayload,
    this.replyPayload,
  });

  factory InboxMessage.fromRow(Map<String, dynamic> row) {
    DateTime? parseTs(Object? raw) =>
        raw is String ? DateTime.parse(raw) : null;

    return InboxMessage(
      id: row['id'] as String,
      kind: InboxMessageKind.fromWire(row['kind'] as String),
      subject: row['subject'] as String,
      body: row['body'] as String,
      sentAt: DateTime.parse(row['sent_at'] as String),
      readAt: parseTs(row['read_at']),
      repliedAt: parseTs(row['replied_at']),
      archivedAt: parseTs(row['archived_at']),
      actionPayload: row['action_payload'] as Map<String, dynamic>?,
      replyPayload: row['reply_payload'] as Map<String, dynamic>?,
    );
  }

  final String id;
  final InboxMessageKind kind;
  final String subject;
  final String body;
  final DateTime sentAt;
  final DateTime? readAt;
  final DateTime? repliedAt;
  final DateTime? archivedAt;
  final Map<String, dynamic>? actionPayload;
  final Map<String, dynamic>? replyPayload;

  bool get isUnread => readAt == null && archivedAt == null;
  bool get awaitsReply =>
      kind == InboxMessageKind.verificationRequest && repliedAt == null;
}
