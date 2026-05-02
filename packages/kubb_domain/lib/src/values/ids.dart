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
