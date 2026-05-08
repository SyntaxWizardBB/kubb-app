import 'package:kubb_app/features/match/data/match_models.dart';

/// One slot inside a [MatchConfigDraft] team line-up. Two flavours:
///
///  * [SelfSlot] — the caller themselves; resolved server-side via the
///    caller's auth user id.
///  * [FriendSlot] — another in-app user (added via friend search /
///    group picker).
sealed class TeamSlot {
  const TeamSlot();

  /// Stable id used by the wizard UI to differentiate slots in lists
  /// and to drive remove/move operations. Must be unique within a draft.
  String get localId;
}

class SelfSlot extends TeamSlot {
  const SelfSlot();

  @override
  String get localId => '__self__';
}

class FriendSlot extends TeamSlot {
  const FriendSlot({required this.userId, required this.nickname});

  /// auth.users.id of the friend.
  final String userId;
  final String nickname;

  @override
  String get localId => 'friend:$userId';
}

extension TeamSlotJson on TeamSlot {
  /// Serialises a slot into the shape expected by the `match_create`
  /// RPC's `p_team_a` / `p_team_b` array elements.
  Map<String, dynamic> toRpcArgs(String? callerUserId) {
    final slot = this;
    switch (slot) {
      case SelfSlot():
        if (callerUserId == null) {
          throw StateError(
            'SelfSlot requires an authenticated caller user id',
          );
        }
        return <String, dynamic>{
          'kind': 'in_app',
          'user_id': callerUserId,
        };
      case FriendSlot():
        return <String, dynamic>{
          'kind': 'in_app',
          'user_id': slot.userId,
        };
    }
  }
}

/// Tag for the two-team layout. The wizard only ever has 'A' and 'B';
/// this enum keeps that explicit at the API surface.
enum MatchTeamTag {
  a,
  b;

  String get wireId {
    switch (this) {
      case MatchTeamTag.a:
        return 'A';
      case MatchTeamTag.b:
        return 'B';
    }
  }
}

/// Outcome of [MatchConfigDraft.validate]. Empty `issues` list means
/// the draft is acceptable for `match_create`.
class MatchConfigValidation {
  const MatchConfigValidation({required this.issues});

  const MatchConfigValidation.ok() : issues = const <String>[];

  final List<String> issues;

  bool get isValid => issues.isEmpty;
}

/// Mutable wizard state for the multi-player match configuration
/// screen. Held by `MatchConfigController`.
class MatchConfigDraft {
  const MatchConfigDraft({
    this.format = MatchFormat.bo1,
    this.scoring = MatchScoring.wins,
    this.teamA = const <TeamSlot>[],
    this.teamB = const <TeamSlot>[],
  });

  final MatchFormat format;
  final MatchScoring scoring;
  final List<TeamSlot> teamA;
  final List<TeamSlot> teamB;

  static const int _minTeamSize = 1;
  static const int _maxTeamSize = 6;

  MatchConfigDraft copyWith({
    MatchFormat? format,
    MatchScoring? scoring,
    List<TeamSlot>? teamA,
    List<TeamSlot>? teamB,
  }) {
    return MatchConfigDraft(
      format: format ?? this.format,
      scoring: scoring ?? this.scoring,
      teamA: teamA ?? this.teamA,
      teamB: teamB ?? this.teamB,
    );
  }

  Iterable<TeamSlot> get allSlots sync* {
    yield* teamA;
    yield* teamB;
  }

  bool get containsSelf => allSlots.any((s) => s is SelfSlot);

  /// Returns the team that currently holds [slot], or null if the
  /// slot is not in either team.
  MatchTeamTag? teamOf(TeamSlot slot) {
    if (teamA.any((s) => s.localId == slot.localId)) {
      return MatchTeamTag.a;
    }
    if (teamB.any((s) => s.localId == slot.localId)) {
      return MatchTeamTag.b;
    }
    return null;
  }

  MatchConfigValidation validate() {
    final issues = <String>[];
    if (teamA.length < _minTeamSize || teamA.length > _maxTeamSize) {
      issues.add('Team A muss 1 bis $_maxTeamSize Spieler enthalten.');
    }
    if (teamB.length < _minTeamSize || teamB.length > _maxTeamSize) {
      issues.add('Team B muss 1 bis $_maxTeamSize Spieler enthalten.');
    }

    if (!containsSelf) {
      issues.add('Du musst selbst einem Team angehören.');
    }

    return MatchConfigValidation(issues: issues);
  }
}
