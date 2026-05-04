// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'restore_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RestoreState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RestoreState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RestoreState()';
}


}

/// @nodoc
class $RestoreStateCopyWith<$Res>  {
$RestoreStateCopyWith(RestoreState _, $Res Function(RestoreState) __);
}


/// Adds pattern-matching-related methods to [RestoreState].
extension RestoreStatePatterns on RestoreState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _RestoreIdle value)?  idle,TResult Function( _RestoreCooldown value)?  cooldown,TResult Function( _Restoring value)?  restoring,TResult Function( _RestoreDone value)?  done,TResult Function( _RestoreFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RestoreIdle() when idle != null:
return idle(_that);case _RestoreCooldown() when cooldown != null:
return cooldown(_that);case _Restoring() when restoring != null:
return restoring(_that);case _RestoreDone() when done != null:
return done(_that);case _RestoreFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _RestoreIdle value)  idle,required TResult Function( _RestoreCooldown value)  cooldown,required TResult Function( _Restoring value)  restoring,required TResult Function( _RestoreDone value)  done,required TResult Function( _RestoreFailed value)  failed,}){
final _that = this;
switch (_that) {
case _RestoreIdle():
return idle(_that);case _RestoreCooldown():
return cooldown(_that);case _Restoring():
return restoring(_that);case _RestoreDone():
return done(_that);case _RestoreFailed():
return failed(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _RestoreIdle value)?  idle,TResult? Function( _RestoreCooldown value)?  cooldown,TResult? Function( _Restoring value)?  restoring,TResult? Function( _RestoreDone value)?  done,TResult? Function( _RestoreFailed value)?  failed,}){
final _that = this;
switch (_that) {
case _RestoreIdle() when idle != null:
return idle(_that);case _RestoreCooldown() when cooldown != null:
return cooldown(_that);case _Restoring() when restoring != null:
return restoring(_that);case _RestoreDone() when done != null:
return done(_that);case _RestoreFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( DateTime until)?  cooldown,TResult Function()?  restoring,TResult Function( String userId)?  done,TResult Function( String reason)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RestoreIdle() when idle != null:
return idle();case _RestoreCooldown() when cooldown != null:
return cooldown(_that.until);case _Restoring() when restoring != null:
return restoring();case _RestoreDone() when done != null:
return done(_that.userId);case _RestoreFailed() when failed != null:
return failed(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( DateTime until)  cooldown,required TResult Function()  restoring,required TResult Function( String userId)  done,required TResult Function( String reason)  failed,}) {final _that = this;
switch (_that) {
case _RestoreIdle():
return idle();case _RestoreCooldown():
return cooldown(_that.until);case _Restoring():
return restoring();case _RestoreDone():
return done(_that.userId);case _RestoreFailed():
return failed(_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( DateTime until)?  cooldown,TResult? Function()?  restoring,TResult? Function( String userId)?  done,TResult? Function( String reason)?  failed,}) {final _that = this;
switch (_that) {
case _RestoreIdle() when idle != null:
return idle();case _RestoreCooldown() when cooldown != null:
return cooldown(_that.until);case _Restoring() when restoring != null:
return restoring();case _RestoreDone() when done != null:
return done(_that.userId);case _RestoreFailed() when failed != null:
return failed(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _RestoreIdle implements RestoreState {
  const _RestoreIdle();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RestoreIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RestoreState.idle()';
}


}




/// @nodoc


class _RestoreCooldown implements RestoreState {
  const _RestoreCooldown({required this.until});
  

 final  DateTime until;

/// Create a copy of RestoreState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RestoreCooldownCopyWith<_RestoreCooldown> get copyWith => __$RestoreCooldownCopyWithImpl<_RestoreCooldown>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RestoreCooldown&&(identical(other.until, until) || other.until == until));
}


@override
int get hashCode => Object.hash(runtimeType,until);

@override
String toString() {
  return 'RestoreState.cooldown(until: $until)';
}


}

/// @nodoc
abstract mixin class _$RestoreCooldownCopyWith<$Res> implements $RestoreStateCopyWith<$Res> {
  factory _$RestoreCooldownCopyWith(_RestoreCooldown value, $Res Function(_RestoreCooldown) _then) = __$RestoreCooldownCopyWithImpl;
@useResult
$Res call({
 DateTime until
});




}
/// @nodoc
class __$RestoreCooldownCopyWithImpl<$Res>
    implements _$RestoreCooldownCopyWith<$Res> {
  __$RestoreCooldownCopyWithImpl(this._self, this._then);

  final _RestoreCooldown _self;
  final $Res Function(_RestoreCooldown) _then;

/// Create a copy of RestoreState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? until = null,}) {
  return _then(_RestoreCooldown(
until: null == until ? _self.until : until // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

/// @nodoc


class _Restoring implements RestoreState {
  const _Restoring();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Restoring);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RestoreState.restoring()';
}


}




/// @nodoc


class _RestoreDone implements RestoreState {
  const _RestoreDone({required this.userId});
  

 final  String userId;

/// Create a copy of RestoreState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RestoreDoneCopyWith<_RestoreDone> get copyWith => __$RestoreDoneCopyWithImpl<_RestoreDone>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RestoreDone&&(identical(other.userId, userId) || other.userId == userId));
}


@override
int get hashCode => Object.hash(runtimeType,userId);

@override
String toString() {
  return 'RestoreState.done(userId: $userId)';
}


}

/// @nodoc
abstract mixin class _$RestoreDoneCopyWith<$Res> implements $RestoreStateCopyWith<$Res> {
  factory _$RestoreDoneCopyWith(_RestoreDone value, $Res Function(_RestoreDone) _then) = __$RestoreDoneCopyWithImpl;
@useResult
$Res call({
 String userId
});




}
/// @nodoc
class __$RestoreDoneCopyWithImpl<$Res>
    implements _$RestoreDoneCopyWith<$Res> {
  __$RestoreDoneCopyWithImpl(this._self, this._then);

  final _RestoreDone _self;
  final $Res Function(_RestoreDone) _then;

/// Create a copy of RestoreState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,}) {
  return _then(_RestoreDone(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class _RestoreFailed implements RestoreState {
  const _RestoreFailed({required this.reason});
  

 final  String reason;

/// Create a copy of RestoreState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RestoreFailedCopyWith<_RestoreFailed> get copyWith => __$RestoreFailedCopyWithImpl<_RestoreFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RestoreFailed&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'RestoreState.failed(reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$RestoreFailedCopyWith<$Res> implements $RestoreStateCopyWith<$Res> {
  factory _$RestoreFailedCopyWith(_RestoreFailed value, $Res Function(_RestoreFailed) _then) = __$RestoreFailedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class __$RestoreFailedCopyWithImpl<$Res>
    implements _$RestoreFailedCopyWith<$Res> {
  __$RestoreFailedCopyWithImpl(this._self, this._then);

  final _RestoreFailed _self;
  final $Res Function(_RestoreFailed) _then;

/// Create a copy of RestoreState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(_RestoreFailed(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
