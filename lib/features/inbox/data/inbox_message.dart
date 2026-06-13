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
  clubJoinRequest,

  /// Berechtigungskonzept (P7): a manager changed this member's role in an
  /// organizer team. Informational; the wire kind stays `club_role_changed`.
  clubRoleChanged,

  /// P6 shoot-out tiebreak task: the involved teams must report and confirm
  /// the shoot-out winner ordering. The D2a server (migration
  /// `20261202000000_tournament_shootout_server.sql`) ships this on the
  /// generic `tournament_round` wire kind but tags the row with
  /// `action_payload['kind'] == 'shootout'`; [fromWire] disambiguates on that
  /// so it routes to the dedicated report/confirm screen instead of the
  /// generic notice rendering.
  tournamentShootout,

  /// N1 tournament-end notification: the tournament has been finalized. Sent
  /// to every participant on the `tournaments.status -> finalized` transition
  /// (migration `20261242000000_tournament_finished_inbox_round_time.sql`).
  /// The body already carries the configured round time, so the UI renders it
  /// as a plain informational message — no action panel.
  tournamentFinished,

  /// Invite-only fun-tournament invitation: the organizer invited this user to
  /// a `invite_only` tournament. Routed to an accept/decline panel; accepting
  /// registers the user as `pending` for that tournament. The action_payload
  /// carries `{tournament_id, invitation_id, tournament_name}`.
  tournamentInvitation,

  /// ADR-0031 Phase C (OD-1): a single *collective* client kind for every
  /// timed-schedule event. The server ships them all on the existing
  /// `tournament_round` wire kind (no new wire-kinds — like shoot-out) and
  /// distinguishes the concrete event purely through
  /// `action_payload['kind']`, one of the C-event sammel-tags
  /// {round_published, match_running, paused, resumed, awaiting_results,
  /// tiebreak_hold}. The per-event label/icon is derived from that payload
  /// tag in the UI; the DB kind-CHECK stays stable (client-side
  /// disambiguation only).
  tournamentSchedule;

  /// The C-event payload tags (`action_payload['kind']`) that all map onto
  /// the collective [tournamentSchedule] kind (OD-1). Kept in one place so
  /// [fromWire] and the UI label/icon helper stay in sync.
  static const Set<String> scheduleEventTags = {
    'round_published',
    'match_running',
    'paused',
    'resumed',
    'awaiting_results',
    'tiebreak_hold',
  };

  /// Maps the wire `kind` plus the row's [actionPayload] onto a typed kind.
  ///
  /// Most kinds map 1:1 from [raw]. The shoot-out task is the exception: the
  /// server emits it as `tournament_round` (already in the inbox kind CHECK)
  /// and only distinguishes it via `action_payload['kind'] == 'shootout'`, so
  /// the disambiguation has to look at [actionPayload] too.
  static InboxMessageKind fromWire(
    String raw, {
    Map<String, dynamic>? actionPayload,
  }) {
    // Shoot-out disambiguation: raw == 'tournament_round' carries the generic
    // round notification AND the shoot-out task; only the action_payload kind
    // separates them.
    if (raw == 'tournament_round' &&
        actionPayload?['kind'] == 'shootout') {
      return InboxMessageKind.tournamentShootout;
    }
    // ADR-0031 Phase C (OD-1): every timed-schedule event also rides on the
    // 'tournament_round' wire kind and is tagged via action_payload['kind']
    // with one of the C-event sammel-tags. They collapse onto the single
    // collective tournamentSchedule kind; the per-event label/icon is derived
    // from the payload tag in the UI. An unknown/absent kind keeps the
    // existing notice fallback below.
    if (raw == 'tournament_round' &&
        scheduleEventTags.contains(actionPayload?['kind'])) {
      return InboxMessageKind.tournamentSchedule;
    }
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
      case 'club_role_changed':
        return InboxMessageKind.clubRoleChanged;
      case 'tournament_finished':
        return InboxMessageKind.tournamentFinished;
      case 'tournament_invitation':
        return InboxMessageKind.tournamentInvitation;
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

    final actionPayload = row['action_payload'] as Map<String, dynamic>?;
    return InboxMessage(
      id: row['id'] as String,
      kind: InboxMessageKind.fromWire(
        row['kind'] as String,
        actionPayload: actionPayload,
      ),
      subject: row['subject'] as String,
      body: row['body'] as String,
      sentAt: DateTime.parse(row['sent_at'] as String),
      readAt: parseTs(row['read_at']),
      repliedAt: parseTs(row['replied_at']),
      archivedAt: parseTs(row['archived_at']),
      actionPayload: actionPayload,
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
