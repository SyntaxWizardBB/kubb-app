/// Relationship state between the calling user and a friend candidate.
/// Mirrors the `relationship` column returned by
/// `friend_search_by_username` and used in `friend_list_for_caller`.
enum FriendRelationship {
  none,
  pendingOutgoing,
  pendingIncoming,
  accepted;

  static FriendRelationship fromWire(String? raw) {
    switch (raw) {
      case 'pending_outgoing':
        return FriendRelationship.pendingOutgoing;
      case 'pending_incoming':
        return FriendRelationship.pendingIncoming;
      case 'accepted':
        return FriendRelationship.accepted;
      default:
        return FriendRelationship.none;
    }
  }
}

/// Search result item — a candidate friend with the caller's current
/// relationship state filled in. Drives both the search UI and the
/// "ist schon Freund" button-state.
class FriendCandidate {
  const FriendCandidate({
    required this.userId,
    required this.nickname,
    required this.relationship,
  });

  factory FriendCandidate.fromRow(Map<String, dynamic> row) {
    return FriendCandidate(
      userId: row['user_id'] as String,
      nickname: row['nickname'] as String,
      relationship:
          FriendRelationship.fromWire(row['relationship'] as String?),
    );
  }

  final String userId;
  final String nickname;
  final FriendRelationship relationship;
}

/// One row of the calling user's friend list — accepted or pending
/// (outgoing or incoming). Sorted by the RPC so incoming requests
/// surface at the top.
class FriendEntry {
  const FriendEntry({
    required this.userId,
    required this.nickname,
    required this.status,
    required this.requestedBy,
    required this.sinceAt,
  });

  factory FriendEntry.fromRow(Map<String, dynamic> row) {
    return FriendEntry(
      userId: row['user_id'] as String,
      nickname: row['nickname'] as String,
      status: row['status'] as String,
      requestedBy: row['requested_by'] as String,
      sinceAt: DateTime.parse(row['since_at'] as String),
    );
  }

  final String userId;
  final String nickname;

  /// 'pending' or 'accepted'.
  final String status;

  /// uuid of the user who originally sent the request. Combined with the
  /// caller's id this yields the [FriendRelationship] needed by the UI.
  final String requestedBy;

  /// `accepted_at` if accepted, else `requested_at`.
  final DateTime sinceAt;

  bool get isAccepted => status == 'accepted';
  bool get isPending => status == 'pending';
}
