// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'team_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TeamWire {

@JsonKey(name: 'team_id') String get id;@JsonKey(name: 'display_name') String get displayName;@JsonKey(name: 'league_membership') String get leagueMembership;@JsonKey(name: 'created_at') DateTime get createdAt;@JsonKey(name: 'logo_url') String? get logoUrl; String? get country;@JsonKey(name: 'dissolved_at') DateTime? get dissolvedAt;
/// Create a copy of TeamWire
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TeamWireCopyWith<TeamWire> get copyWith => _$TeamWireCopyWithImpl<TeamWire>(this as TeamWire, _$identity);

  /// Serializes this TeamWire to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TeamWire&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.leagueMembership, leagueMembership) || other.leagueMembership == leagueMembership)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.logoUrl, logoUrl) || other.logoUrl == logoUrl)&&(identical(other.country, country) || other.country == country)&&(identical(other.dissolvedAt, dissolvedAt) || other.dissolvedAt == dissolvedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,displayName,leagueMembership,createdAt,logoUrl,country,dissolvedAt);

@override
String toString() {
  return 'TeamWire(id: $id, displayName: $displayName, leagueMembership: $leagueMembership, createdAt: $createdAt, logoUrl: $logoUrl, country: $country, dissolvedAt: $dissolvedAt)';
}


}

/// @nodoc
abstract mixin class $TeamWireCopyWith<$Res>  {
  factory $TeamWireCopyWith(TeamWire value, $Res Function(TeamWire) _then) = _$TeamWireCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'team_id') String id,@JsonKey(name: 'display_name') String displayName,@JsonKey(name: 'league_membership') String leagueMembership,@JsonKey(name: 'created_at') DateTime createdAt,@JsonKey(name: 'logo_url') String? logoUrl, String? country,@JsonKey(name: 'dissolved_at') DateTime? dissolvedAt
});




}
/// @nodoc
class _$TeamWireCopyWithImpl<$Res>
    implements $TeamWireCopyWith<$Res> {
  _$TeamWireCopyWithImpl(this._self, this._then);

  final TeamWire _self;
  final $Res Function(TeamWire) _then;

/// Create a copy of TeamWire
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? leagueMembership = null,Object? createdAt = null,Object? logoUrl = freezed,Object? country = freezed,Object? dissolvedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,leagueMembership: null == leagueMembership ? _self.leagueMembership : leagueMembership // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,logoUrl: freezed == logoUrl ? _self.logoUrl : logoUrl // ignore: cast_nullable_to_non_nullable
as String?,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String?,dissolvedAt: freezed == dissolvedAt ? _self.dissolvedAt : dissolvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [TeamWire].
extension TeamWirePatterns on TeamWire {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TeamWire value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TeamWire() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TeamWire value)  $default,){
final _that = this;
switch (_that) {
case _TeamWire():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TeamWire value)?  $default,){
final _that = this;
switch (_that) {
case _TeamWire() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'team_id')  String id, @JsonKey(name: 'display_name')  String displayName, @JsonKey(name: 'league_membership')  String leagueMembership, @JsonKey(name: 'created_at')  DateTime createdAt, @JsonKey(name: 'logo_url')  String? logoUrl,  String? country, @JsonKey(name: 'dissolved_at')  DateTime? dissolvedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TeamWire() when $default != null:
return $default(_that.id,_that.displayName,_that.leagueMembership,_that.createdAt,_that.logoUrl,_that.country,_that.dissolvedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'team_id')  String id, @JsonKey(name: 'display_name')  String displayName, @JsonKey(name: 'league_membership')  String leagueMembership, @JsonKey(name: 'created_at')  DateTime createdAt, @JsonKey(name: 'logo_url')  String? logoUrl,  String? country, @JsonKey(name: 'dissolved_at')  DateTime? dissolvedAt)  $default,) {final _that = this;
switch (_that) {
case _TeamWire():
return $default(_that.id,_that.displayName,_that.leagueMembership,_that.createdAt,_that.logoUrl,_that.country,_that.dissolvedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'team_id')  String id, @JsonKey(name: 'display_name')  String displayName, @JsonKey(name: 'league_membership')  String leagueMembership, @JsonKey(name: 'created_at')  DateTime createdAt, @JsonKey(name: 'logo_url')  String? logoUrl,  String? country, @JsonKey(name: 'dissolved_at')  DateTime? dissolvedAt)?  $default,) {final _that = this;
switch (_that) {
case _TeamWire() when $default != null:
return $default(_that.id,_that.displayName,_that.leagueMembership,_that.createdAt,_that.logoUrl,_that.country,_that.dissolvedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TeamWire implements TeamWire {
  const _TeamWire({@JsonKey(name: 'team_id') required this.id, @JsonKey(name: 'display_name') required this.displayName, @JsonKey(name: 'league_membership') required this.leagueMembership, @JsonKey(name: 'created_at') required this.createdAt, @JsonKey(name: 'logo_url') this.logoUrl, this.country, @JsonKey(name: 'dissolved_at') this.dissolvedAt});
  factory _TeamWire.fromJson(Map<String, dynamic> json) => _$TeamWireFromJson(json);

@override@JsonKey(name: 'team_id') final  String id;
@override@JsonKey(name: 'display_name') final  String displayName;
@override@JsonKey(name: 'league_membership') final  String leagueMembership;
@override@JsonKey(name: 'created_at') final  DateTime createdAt;
@override@JsonKey(name: 'logo_url') final  String? logoUrl;
@override final  String? country;
@override@JsonKey(name: 'dissolved_at') final  DateTime? dissolvedAt;

/// Create a copy of TeamWire
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TeamWireCopyWith<_TeamWire> get copyWith => __$TeamWireCopyWithImpl<_TeamWire>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TeamWireToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TeamWire&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.leagueMembership, leagueMembership) || other.leagueMembership == leagueMembership)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.logoUrl, logoUrl) || other.logoUrl == logoUrl)&&(identical(other.country, country) || other.country == country)&&(identical(other.dissolvedAt, dissolvedAt) || other.dissolvedAt == dissolvedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,displayName,leagueMembership,createdAt,logoUrl,country,dissolvedAt);

@override
String toString() {
  return 'TeamWire(id: $id, displayName: $displayName, leagueMembership: $leagueMembership, createdAt: $createdAt, logoUrl: $logoUrl, country: $country, dissolvedAt: $dissolvedAt)';
}


}

/// @nodoc
abstract mixin class _$TeamWireCopyWith<$Res> implements $TeamWireCopyWith<$Res> {
  factory _$TeamWireCopyWith(_TeamWire value, $Res Function(_TeamWire) _then) = __$TeamWireCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'team_id') String id,@JsonKey(name: 'display_name') String displayName,@JsonKey(name: 'league_membership') String leagueMembership,@JsonKey(name: 'created_at') DateTime createdAt,@JsonKey(name: 'logo_url') String? logoUrl, String? country,@JsonKey(name: 'dissolved_at') DateTime? dissolvedAt
});




}
/// @nodoc
class __$TeamWireCopyWithImpl<$Res>
    implements _$TeamWireCopyWith<$Res> {
  __$TeamWireCopyWithImpl(this._self, this._then);

  final _TeamWire _self;
  final $Res Function(_TeamWire) _then;

/// Create a copy of TeamWire
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? leagueMembership = null,Object? createdAt = null,Object? logoUrl = freezed,Object? country = freezed,Object? dissolvedAt = freezed,}) {
  return _then(_TeamWire(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,leagueMembership: null == leagueMembership ? _self.leagueMembership : leagueMembership // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,logoUrl: freezed == logoUrl ? _self.logoUrl : logoUrl // ignore: cast_nullable_to_non_nullable
as String?,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String?,dissolvedAt: freezed == dissolvedAt ? _self.dissolvedAt : dissolvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


/// @nodoc
mixin _$TeamMembershipWire {

@JsonKey(name: 'membership_id') String get membershipId;@JsonKey(name: 'user_id') String get userId;@JsonKey(name: 'joined_at') DateTime get joinedAt;
/// Create a copy of TeamMembershipWire
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TeamMembershipWireCopyWith<TeamMembershipWire> get copyWith => _$TeamMembershipWireCopyWithImpl<TeamMembershipWire>(this as TeamMembershipWire, _$identity);

  /// Serializes this TeamMembershipWire to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TeamMembershipWire&&(identical(other.membershipId, membershipId) || other.membershipId == membershipId)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.joinedAt, joinedAt) || other.joinedAt == joinedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,membershipId,userId,joinedAt);

@override
String toString() {
  return 'TeamMembershipWire(membershipId: $membershipId, userId: $userId, joinedAt: $joinedAt)';
}


}

/// @nodoc
abstract mixin class $TeamMembershipWireCopyWith<$Res>  {
  factory $TeamMembershipWireCopyWith(TeamMembershipWire value, $Res Function(TeamMembershipWire) _then) = _$TeamMembershipWireCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'membership_id') String membershipId,@JsonKey(name: 'user_id') String userId,@JsonKey(name: 'joined_at') DateTime joinedAt
});




}
/// @nodoc
class _$TeamMembershipWireCopyWithImpl<$Res>
    implements $TeamMembershipWireCopyWith<$Res> {
  _$TeamMembershipWireCopyWithImpl(this._self, this._then);

  final TeamMembershipWire _self;
  final $Res Function(TeamMembershipWire) _then;

/// Create a copy of TeamMembershipWire
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? membershipId = null,Object? userId = null,Object? joinedAt = null,}) {
  return _then(_self.copyWith(
membershipId: null == membershipId ? _self.membershipId : membershipId // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,joinedAt: null == joinedAt ? _self.joinedAt : joinedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [TeamMembershipWire].
extension TeamMembershipWirePatterns on TeamMembershipWire {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TeamMembershipWire value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TeamMembershipWire() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TeamMembershipWire value)  $default,){
final _that = this;
switch (_that) {
case _TeamMembershipWire():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TeamMembershipWire value)?  $default,){
final _that = this;
switch (_that) {
case _TeamMembershipWire() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'membership_id')  String membershipId, @JsonKey(name: 'user_id')  String userId, @JsonKey(name: 'joined_at')  DateTime joinedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TeamMembershipWire() when $default != null:
return $default(_that.membershipId,_that.userId,_that.joinedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'membership_id')  String membershipId, @JsonKey(name: 'user_id')  String userId, @JsonKey(name: 'joined_at')  DateTime joinedAt)  $default,) {final _that = this;
switch (_that) {
case _TeamMembershipWire():
return $default(_that.membershipId,_that.userId,_that.joinedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'membership_id')  String membershipId, @JsonKey(name: 'user_id')  String userId, @JsonKey(name: 'joined_at')  DateTime joinedAt)?  $default,) {final _that = this;
switch (_that) {
case _TeamMembershipWire() when $default != null:
return $default(_that.membershipId,_that.userId,_that.joinedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TeamMembershipWire implements TeamMembershipWire {
  const _TeamMembershipWire({@JsonKey(name: 'membership_id') required this.membershipId, @JsonKey(name: 'user_id') required this.userId, @JsonKey(name: 'joined_at') required this.joinedAt});
  factory _TeamMembershipWire.fromJson(Map<String, dynamic> json) => _$TeamMembershipWireFromJson(json);

@override@JsonKey(name: 'membership_id') final  String membershipId;
@override@JsonKey(name: 'user_id') final  String userId;
@override@JsonKey(name: 'joined_at') final  DateTime joinedAt;

/// Create a copy of TeamMembershipWire
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TeamMembershipWireCopyWith<_TeamMembershipWire> get copyWith => __$TeamMembershipWireCopyWithImpl<_TeamMembershipWire>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TeamMembershipWireToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TeamMembershipWire&&(identical(other.membershipId, membershipId) || other.membershipId == membershipId)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.joinedAt, joinedAt) || other.joinedAt == joinedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,membershipId,userId,joinedAt);

@override
String toString() {
  return 'TeamMembershipWire(membershipId: $membershipId, userId: $userId, joinedAt: $joinedAt)';
}


}

/// @nodoc
abstract mixin class _$TeamMembershipWireCopyWith<$Res> implements $TeamMembershipWireCopyWith<$Res> {
  factory _$TeamMembershipWireCopyWith(_TeamMembershipWire value, $Res Function(_TeamMembershipWire) _then) = __$TeamMembershipWireCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'membership_id') String membershipId,@JsonKey(name: 'user_id') String userId,@JsonKey(name: 'joined_at') DateTime joinedAt
});




}
/// @nodoc
class __$TeamMembershipWireCopyWithImpl<$Res>
    implements _$TeamMembershipWireCopyWith<$Res> {
  __$TeamMembershipWireCopyWithImpl(this._self, this._then);

  final _TeamMembershipWire _self;
  final $Res Function(_TeamMembershipWire) _then;

/// Create a copy of TeamMembershipWire
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? membershipId = null,Object? userId = null,Object? joinedAt = null,}) {
  return _then(_TeamMembershipWire(
membershipId: null == membershipId ? _self.membershipId : membershipId // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,joinedAt: null == joinedAt ? _self.joinedAt : joinedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}


/// @nodoc
mixin _$TeamInvitationWire {

@JsonKey(name: 'invitation_id') String get invitationId;@JsonKey(name: 'team_id') String get teamId;@JsonKey(name: 'invitee_user_id') String get inviteeUserId; String get state;@JsonKey(name: 'created_at') DateTime get createdAt;
/// Create a copy of TeamInvitationWire
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TeamInvitationWireCopyWith<TeamInvitationWire> get copyWith => _$TeamInvitationWireCopyWithImpl<TeamInvitationWire>(this as TeamInvitationWire, _$identity);

  /// Serializes this TeamInvitationWire to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TeamInvitationWire&&(identical(other.invitationId, invitationId) || other.invitationId == invitationId)&&(identical(other.teamId, teamId) || other.teamId == teamId)&&(identical(other.inviteeUserId, inviteeUserId) || other.inviteeUserId == inviteeUserId)&&(identical(other.state, state) || other.state == state)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,invitationId,teamId,inviteeUserId,state,createdAt);

@override
String toString() {
  return 'TeamInvitationWire(invitationId: $invitationId, teamId: $teamId, inviteeUserId: $inviteeUserId, state: $state, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $TeamInvitationWireCopyWith<$Res>  {
  factory $TeamInvitationWireCopyWith(TeamInvitationWire value, $Res Function(TeamInvitationWire) _then) = _$TeamInvitationWireCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'invitation_id') String invitationId,@JsonKey(name: 'team_id') String teamId,@JsonKey(name: 'invitee_user_id') String inviteeUserId, String state,@JsonKey(name: 'created_at') DateTime createdAt
});




}
/// @nodoc
class _$TeamInvitationWireCopyWithImpl<$Res>
    implements $TeamInvitationWireCopyWith<$Res> {
  _$TeamInvitationWireCopyWithImpl(this._self, this._then);

  final TeamInvitationWire _self;
  final $Res Function(TeamInvitationWire) _then;

/// Create a copy of TeamInvitationWire
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? invitationId = null,Object? teamId = null,Object? inviteeUserId = null,Object? state = null,Object? createdAt = null,}) {
  return _then(_self.copyWith(
invitationId: null == invitationId ? _self.invitationId : invitationId // ignore: cast_nullable_to_non_nullable
as String,teamId: null == teamId ? _self.teamId : teamId // ignore: cast_nullable_to_non_nullable
as String,inviteeUserId: null == inviteeUserId ? _self.inviteeUserId : inviteeUserId // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [TeamInvitationWire].
extension TeamInvitationWirePatterns on TeamInvitationWire {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TeamInvitationWire value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TeamInvitationWire() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TeamInvitationWire value)  $default,){
final _that = this;
switch (_that) {
case _TeamInvitationWire():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TeamInvitationWire value)?  $default,){
final _that = this;
switch (_that) {
case _TeamInvitationWire() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'invitation_id')  String invitationId, @JsonKey(name: 'team_id')  String teamId, @JsonKey(name: 'invitee_user_id')  String inviteeUserId,  String state, @JsonKey(name: 'created_at')  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TeamInvitationWire() when $default != null:
return $default(_that.invitationId,_that.teamId,_that.inviteeUserId,_that.state,_that.createdAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'invitation_id')  String invitationId, @JsonKey(name: 'team_id')  String teamId, @JsonKey(name: 'invitee_user_id')  String inviteeUserId,  String state, @JsonKey(name: 'created_at')  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _TeamInvitationWire():
return $default(_that.invitationId,_that.teamId,_that.inviteeUserId,_that.state,_that.createdAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'invitation_id')  String invitationId, @JsonKey(name: 'team_id')  String teamId, @JsonKey(name: 'invitee_user_id')  String inviteeUserId,  String state, @JsonKey(name: 'created_at')  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _TeamInvitationWire() when $default != null:
return $default(_that.invitationId,_that.teamId,_that.inviteeUserId,_that.state,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TeamInvitationWire implements TeamInvitationWire {
  const _TeamInvitationWire({@JsonKey(name: 'invitation_id') required this.invitationId, @JsonKey(name: 'team_id') required this.teamId, @JsonKey(name: 'invitee_user_id') required this.inviteeUserId, required this.state, @JsonKey(name: 'created_at') required this.createdAt});
  factory _TeamInvitationWire.fromJson(Map<String, dynamic> json) => _$TeamInvitationWireFromJson(json);

@override@JsonKey(name: 'invitation_id') final  String invitationId;
@override@JsonKey(name: 'team_id') final  String teamId;
@override@JsonKey(name: 'invitee_user_id') final  String inviteeUserId;
@override final  String state;
@override@JsonKey(name: 'created_at') final  DateTime createdAt;

/// Create a copy of TeamInvitationWire
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TeamInvitationWireCopyWith<_TeamInvitationWire> get copyWith => __$TeamInvitationWireCopyWithImpl<_TeamInvitationWire>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TeamInvitationWireToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TeamInvitationWire&&(identical(other.invitationId, invitationId) || other.invitationId == invitationId)&&(identical(other.teamId, teamId) || other.teamId == teamId)&&(identical(other.inviteeUserId, inviteeUserId) || other.inviteeUserId == inviteeUserId)&&(identical(other.state, state) || other.state == state)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,invitationId,teamId,inviteeUserId,state,createdAt);

@override
String toString() {
  return 'TeamInvitationWire(invitationId: $invitationId, teamId: $teamId, inviteeUserId: $inviteeUserId, state: $state, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$TeamInvitationWireCopyWith<$Res> implements $TeamInvitationWireCopyWith<$Res> {
  factory _$TeamInvitationWireCopyWith(_TeamInvitationWire value, $Res Function(_TeamInvitationWire) _then) = __$TeamInvitationWireCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'invitation_id') String invitationId,@JsonKey(name: 'team_id') String teamId,@JsonKey(name: 'invitee_user_id') String inviteeUserId, String state,@JsonKey(name: 'created_at') DateTime createdAt
});




}
/// @nodoc
class __$TeamInvitationWireCopyWithImpl<$Res>
    implements _$TeamInvitationWireCopyWith<$Res> {
  __$TeamInvitationWireCopyWithImpl(this._self, this._then);

  final _TeamInvitationWire _self;
  final $Res Function(_TeamInvitationWire) _then;

/// Create a copy of TeamInvitationWire
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? invitationId = null,Object? teamId = null,Object? inviteeUserId = null,Object? state = null,Object? createdAt = null,}) {
  return _then(_TeamInvitationWire(
invitationId: null == invitationId ? _self.invitationId : invitationId // ignore: cast_nullable_to_non_nullable
as String,teamId: null == teamId ? _self.teamId : teamId // ignore: cast_nullable_to_non_nullable
as String,inviteeUserId: null == inviteeUserId ? _self.inviteeUserId : inviteeUserId // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}


/// @nodoc
mixin _$GuestPlayerWire {

@JsonKey(name: 'guest_id') String get guestId;@JsonKey(name: 'display_name') String get displayName;@JsonKey(name: 'added_at') DateTime get addedAt;
/// Create a copy of GuestPlayerWire
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GuestPlayerWireCopyWith<GuestPlayerWire> get copyWith => _$GuestPlayerWireCopyWithImpl<GuestPlayerWire>(this as GuestPlayerWire, _$identity);

  /// Serializes this GuestPlayerWire to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GuestPlayerWire&&(identical(other.guestId, guestId) || other.guestId == guestId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.addedAt, addedAt) || other.addedAt == addedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,guestId,displayName,addedAt);

@override
String toString() {
  return 'GuestPlayerWire(guestId: $guestId, displayName: $displayName, addedAt: $addedAt)';
}


}

/// @nodoc
abstract mixin class $GuestPlayerWireCopyWith<$Res>  {
  factory $GuestPlayerWireCopyWith(GuestPlayerWire value, $Res Function(GuestPlayerWire) _then) = _$GuestPlayerWireCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'guest_id') String guestId,@JsonKey(name: 'display_name') String displayName,@JsonKey(name: 'added_at') DateTime addedAt
});




}
/// @nodoc
class _$GuestPlayerWireCopyWithImpl<$Res>
    implements $GuestPlayerWireCopyWith<$Res> {
  _$GuestPlayerWireCopyWithImpl(this._self, this._then);

  final GuestPlayerWire _self;
  final $Res Function(GuestPlayerWire) _then;

/// Create a copy of GuestPlayerWire
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? guestId = null,Object? displayName = null,Object? addedAt = null,}) {
  return _then(_self.copyWith(
guestId: null == guestId ? _self.guestId : guestId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,addedAt: null == addedAt ? _self.addedAt : addedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [GuestPlayerWire].
extension GuestPlayerWirePatterns on GuestPlayerWire {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GuestPlayerWire value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GuestPlayerWire() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GuestPlayerWire value)  $default,){
final _that = this;
switch (_that) {
case _GuestPlayerWire():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GuestPlayerWire value)?  $default,){
final _that = this;
switch (_that) {
case _GuestPlayerWire() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'guest_id')  String guestId, @JsonKey(name: 'display_name')  String displayName, @JsonKey(name: 'added_at')  DateTime addedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GuestPlayerWire() when $default != null:
return $default(_that.guestId,_that.displayName,_that.addedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'guest_id')  String guestId, @JsonKey(name: 'display_name')  String displayName, @JsonKey(name: 'added_at')  DateTime addedAt)  $default,) {final _that = this;
switch (_that) {
case _GuestPlayerWire():
return $default(_that.guestId,_that.displayName,_that.addedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'guest_id')  String guestId, @JsonKey(name: 'display_name')  String displayName, @JsonKey(name: 'added_at')  DateTime addedAt)?  $default,) {final _that = this;
switch (_that) {
case _GuestPlayerWire() when $default != null:
return $default(_that.guestId,_that.displayName,_that.addedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GuestPlayerWire implements GuestPlayerWire {
  const _GuestPlayerWire({@JsonKey(name: 'guest_id') required this.guestId, @JsonKey(name: 'display_name') required this.displayName, @JsonKey(name: 'added_at') required this.addedAt});
  factory _GuestPlayerWire.fromJson(Map<String, dynamic> json) => _$GuestPlayerWireFromJson(json);

@override@JsonKey(name: 'guest_id') final  String guestId;
@override@JsonKey(name: 'display_name') final  String displayName;
@override@JsonKey(name: 'added_at') final  DateTime addedAt;

/// Create a copy of GuestPlayerWire
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GuestPlayerWireCopyWith<_GuestPlayerWire> get copyWith => __$GuestPlayerWireCopyWithImpl<_GuestPlayerWire>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GuestPlayerWireToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GuestPlayerWire&&(identical(other.guestId, guestId) || other.guestId == guestId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.addedAt, addedAt) || other.addedAt == addedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,guestId,displayName,addedAt);

@override
String toString() {
  return 'GuestPlayerWire(guestId: $guestId, displayName: $displayName, addedAt: $addedAt)';
}


}

/// @nodoc
abstract mixin class _$GuestPlayerWireCopyWith<$Res> implements $GuestPlayerWireCopyWith<$Res> {
  factory _$GuestPlayerWireCopyWith(_GuestPlayerWire value, $Res Function(_GuestPlayerWire) _then) = __$GuestPlayerWireCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'guest_id') String guestId,@JsonKey(name: 'display_name') String displayName,@JsonKey(name: 'added_at') DateTime addedAt
});




}
/// @nodoc
class __$GuestPlayerWireCopyWithImpl<$Res>
    implements _$GuestPlayerWireCopyWith<$Res> {
  __$GuestPlayerWireCopyWithImpl(this._self, this._then);

  final _GuestPlayerWire _self;
  final $Res Function(_GuestPlayerWire) _then;

/// Create a copy of GuestPlayerWire
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? guestId = null,Object? displayName = null,Object? addedAt = null,}) {
  return _then(_GuestPlayerWire(
guestId: null == guestId ? _self.guestId : guestId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,addedAt: null == addedAt ? _self.addedAt : addedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
