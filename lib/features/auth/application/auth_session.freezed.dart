// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'auth_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AuthSession {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthSession);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AuthSession()';
}


}

/// @nodoc
class $AuthSessionCopyWith<$Res>  {
$AuthSessionCopyWith(AuthSession _, $Res Function(AuthSession) __);
}


/// Adds pattern-matching-related methods to [AuthSession].
extension AuthSessionPatterns on AuthSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SignedOutSession value)?  signedOut,TResult Function( AnonymousSession value)?  anonymous,TResult Function( KeypairSession value)?  keypair,TResult Function( OAuthSession value)?  oauth,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SignedOutSession() when signedOut != null:
return signedOut(_that);case AnonymousSession() when anonymous != null:
return anonymous(_that);case KeypairSession() when keypair != null:
return keypair(_that);case OAuthSession() when oauth != null:
return oauth(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SignedOutSession value)  signedOut,required TResult Function( AnonymousSession value)  anonymous,required TResult Function( KeypairSession value)  keypair,required TResult Function( OAuthSession value)  oauth,}){
final _that = this;
switch (_that) {
case SignedOutSession():
return signedOut(_that);case AnonymousSession():
return anonymous(_that);case KeypairSession():
return keypair(_that);case OAuthSession():
return oauth(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SignedOutSession value)?  signedOut,TResult? Function( AnonymousSession value)?  anonymous,TResult? Function( KeypairSession value)?  keypair,TResult? Function( OAuthSession value)?  oauth,}){
final _that = this;
switch (_that) {
case SignedOutSession() when signedOut != null:
return signedOut(_that);case AnonymousSession() when anonymous != null:
return anonymous(_that);case KeypairSession() when keypair != null:
return keypair(_that);case OAuthSession() when oauth != null:
return oauth(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  signedOut,TResult Function( String userId)?  anonymous,TResult Function( String userId,  String displayName,  String? avatarColor)?  keypair,TResult Function( String userId,  String displayName,  AuthProvider provider,  String? avatarColor,  bool hasKeypairFallback)?  oauth,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SignedOutSession() when signedOut != null:
return signedOut();case AnonymousSession() when anonymous != null:
return anonymous(_that.userId);case KeypairSession() when keypair != null:
return keypair(_that.userId,_that.displayName,_that.avatarColor);case OAuthSession() when oauth != null:
return oauth(_that.userId,_that.displayName,_that.provider,_that.avatarColor,_that.hasKeypairFallback);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  signedOut,required TResult Function( String userId)  anonymous,required TResult Function( String userId,  String displayName,  String? avatarColor)  keypair,required TResult Function( String userId,  String displayName,  AuthProvider provider,  String? avatarColor,  bool hasKeypairFallback)  oauth,}) {final _that = this;
switch (_that) {
case SignedOutSession():
return signedOut();case AnonymousSession():
return anonymous(_that.userId);case KeypairSession():
return keypair(_that.userId,_that.displayName,_that.avatarColor);case OAuthSession():
return oauth(_that.userId,_that.displayName,_that.provider,_that.avatarColor,_that.hasKeypairFallback);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  signedOut,TResult? Function( String userId)?  anonymous,TResult? Function( String userId,  String displayName,  String? avatarColor)?  keypair,TResult? Function( String userId,  String displayName,  AuthProvider provider,  String? avatarColor,  bool hasKeypairFallback)?  oauth,}) {final _that = this;
switch (_that) {
case SignedOutSession() when signedOut != null:
return signedOut();case AnonymousSession() when anonymous != null:
return anonymous(_that.userId);case KeypairSession() when keypair != null:
return keypair(_that.userId,_that.displayName,_that.avatarColor);case OAuthSession() when oauth != null:
return oauth(_that.userId,_that.displayName,_that.provider,_that.avatarColor,_that.hasKeypairFallback);case _:
  return null;

}
}

}

/// @nodoc


class SignedOutSession extends AuthSession {
  const SignedOutSession(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SignedOutSession);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AuthSession.signedOut()';
}


}




/// @nodoc


class AnonymousSession extends AuthSession {
  const AnonymousSession({required this.userId}): super._();
  

 final  String userId;

/// Create a copy of AuthSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnonymousSessionCopyWith<AnonymousSession> get copyWith => _$AnonymousSessionCopyWithImpl<AnonymousSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AnonymousSession&&(identical(other.userId, userId) || other.userId == userId));
}


@override
int get hashCode => Object.hash(runtimeType,userId);

@override
String toString() {
  return 'AuthSession.anonymous(userId: $userId)';
}


}

/// @nodoc
abstract mixin class $AnonymousSessionCopyWith<$Res> implements $AuthSessionCopyWith<$Res> {
  factory $AnonymousSessionCopyWith(AnonymousSession value, $Res Function(AnonymousSession) _then) = _$AnonymousSessionCopyWithImpl;
@useResult
$Res call({
 String userId
});




}
/// @nodoc
class _$AnonymousSessionCopyWithImpl<$Res>
    implements $AnonymousSessionCopyWith<$Res> {
  _$AnonymousSessionCopyWithImpl(this._self, this._then);

  final AnonymousSession _self;
  final $Res Function(AnonymousSession) _then;

/// Create a copy of AuthSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,}) {
  return _then(AnonymousSession(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class KeypairSession extends AuthSession {
  const KeypairSession({required this.userId, required this.displayName, this.avatarColor}): super._();
  

 final  String userId;
 final  String displayName;
 final  String? avatarColor;

/// Create a copy of AuthSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$KeypairSessionCopyWith<KeypairSession> get copyWith => _$KeypairSessionCopyWithImpl<KeypairSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is KeypairSession&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.avatarColor, avatarColor) || other.avatarColor == avatarColor));
}


@override
int get hashCode => Object.hash(runtimeType,userId,displayName,avatarColor);

@override
String toString() {
  return 'AuthSession.keypair(userId: $userId, displayName: $displayName, avatarColor: $avatarColor)';
}


}

/// @nodoc
abstract mixin class $KeypairSessionCopyWith<$Res> implements $AuthSessionCopyWith<$Res> {
  factory $KeypairSessionCopyWith(KeypairSession value, $Res Function(KeypairSession) _then) = _$KeypairSessionCopyWithImpl;
@useResult
$Res call({
 String userId, String displayName, String? avatarColor
});




}
/// @nodoc
class _$KeypairSessionCopyWithImpl<$Res>
    implements $KeypairSessionCopyWith<$Res> {
  _$KeypairSessionCopyWithImpl(this._self, this._then);

  final KeypairSession _self;
  final $Res Function(KeypairSession) _then;

/// Create a copy of AuthSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? displayName = null,Object? avatarColor = freezed,}) {
  return _then(KeypairSession(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,avatarColor: freezed == avatarColor ? _self.avatarColor : avatarColor // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class OAuthSession extends AuthSession {
  const OAuthSession({required this.userId, required this.displayName, required this.provider, this.avatarColor, this.hasKeypairFallback = false}): super._();
  

 final  String userId;
 final  String displayName;
 final  AuthProvider provider;
 final  String? avatarColor;
@JsonKey() final  bool hasKeypairFallback;

/// Create a copy of AuthSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OAuthSessionCopyWith<OAuthSession> get copyWith => _$OAuthSessionCopyWithImpl<OAuthSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OAuthSession&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.avatarColor, avatarColor) || other.avatarColor == avatarColor)&&(identical(other.hasKeypairFallback, hasKeypairFallback) || other.hasKeypairFallback == hasKeypairFallback));
}


@override
int get hashCode => Object.hash(runtimeType,userId,displayName,provider,avatarColor,hasKeypairFallback);

@override
String toString() {
  return 'AuthSession.oauth(userId: $userId, displayName: $displayName, provider: $provider, avatarColor: $avatarColor, hasKeypairFallback: $hasKeypairFallback)';
}


}

/// @nodoc
abstract mixin class $OAuthSessionCopyWith<$Res> implements $AuthSessionCopyWith<$Res> {
  factory $OAuthSessionCopyWith(OAuthSession value, $Res Function(OAuthSession) _then) = _$OAuthSessionCopyWithImpl;
@useResult
$Res call({
 String userId, String displayName, AuthProvider provider, String? avatarColor, bool hasKeypairFallback
});




}
/// @nodoc
class _$OAuthSessionCopyWithImpl<$Res>
    implements $OAuthSessionCopyWith<$Res> {
  _$OAuthSessionCopyWithImpl(this._self, this._then);

  final OAuthSession _self;
  final $Res Function(OAuthSession) _then;

/// Create a copy of AuthSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? displayName = null,Object? provider = null,Object? avatarColor = freezed,Object? hasKeypairFallback = null,}) {
  return _then(OAuthSession(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AuthProvider,avatarColor: freezed == avatarColor ? _self.avatarColor : avatarColor // ignore: cast_nullable_to_non_nullable
as String?,hasKeypairFallback: null == hasKeypairFallback ? _self.hasKeypairFallback : hasKeypairFallback // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
