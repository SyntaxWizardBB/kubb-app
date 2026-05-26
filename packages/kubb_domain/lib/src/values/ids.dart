import 'package:meta/meta.dart';

@immutable
sealed class TypedId {
  const TypedId(this.value);
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is TypedId &&
          other.value == value;

  @override
  int get hashCode => Object.hash(_typeTag, value);

  String get _typeTag;

  @override
  String toString() => '$_typeTag($value)';
}

final class MatchId extends TypedId {
  const MatchId(super.value);
  @override
  String get _typeTag => 'MatchId';
}

final class TournamentId extends TypedId {
  const TournamentId(super.value);
  @override
  String get _typeTag => 'TournamentId';
}

final class PlayerId extends TypedId {
  const PlayerId(super.value);
  @override
  String get _typeTag => 'PlayerId';
}

final class TeamId extends TypedId {
  const TeamId(super.value);
  @override
  String get _typeTag => 'TeamId';
}

final class EventId extends TypedId {
  const EventId(super.value);
  @override
  String get _typeTag => 'EventId';
}

final class DeviceId extends TypedId {
  const DeviceId(super.value);
  @override
  String get _typeTag => 'DeviceId';
}

final class TournamentParticipantId extends TypedId {
  const TournamentParticipantId(super.value);
  @override
  String get _typeTag => 'TournamentParticipantId';
}

final class TournamentMatchId extends TypedId {
  const TournamentMatchId(super.value);
  @override
  String get _typeTag => 'TournamentMatchId';
}

final class UserId extends TypedId {
  const UserId(super.value);
  @override
  String get _typeTag => 'UserId';
}

final class TeamGuestPlayerId extends TypedId {
  TeamGuestPlayerId(super.value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'must not be empty');
    }
  }
  @override
  String get _typeTag => 'TeamGuestPlayerId';
}

final class TeamMembershipId extends TypedId {
  TeamMembershipId(super.value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'must not be empty');
    }
  }
  @override
  String get _typeTag => 'TeamMembershipId';
}

final class TeamInvitationId extends TypedId {
  TeamInvitationId(super.value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'must not be empty');
    }
  }
  @override
  String get _typeTag => 'TeamInvitationId';
}
