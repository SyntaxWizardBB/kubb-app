// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account_deletion_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountDeletionState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountDeletionState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AccountDeletionState()';
}


}

/// @nodoc
class $AccountDeletionStateCopyWith<$Res>  {
$AccountDeletionStateCopyWith(AccountDeletionState _, $Res Function(AccountDeletionState) __);
}


/// Adds pattern-matching-related methods to [AccountDeletionState].
extension AccountDeletionStatePatterns on AccountDeletionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _ADIdle value)?  idle,TResult Function( _ADDeleting value)?  deleting,TResult Function( _ADDone value)?  done,TResult Function( _ADFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ADIdle() when idle != null:
return idle(_that);case _ADDeleting() when deleting != null:
return deleting(_that);case _ADDone() when done != null:
return done(_that);case _ADFailed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _ADIdle value)  idle,required TResult Function( _ADDeleting value)  deleting,required TResult Function( _ADDone value)  done,required TResult Function( _ADFailed value)  failed,}){
final _that = this;
switch (_that) {
case _ADIdle():
return idle(_that);case _ADDeleting():
return deleting(_that);case _ADDone():
return done(_that);case _ADFailed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _ADIdle value)?  idle,TResult? Function( _ADDeleting value)?  deleting,TResult? Function( _ADDone value)?  done,TResult? Function( _ADFailed value)?  failed,}){
final _that = this;
switch (_that) {
case _ADIdle() when idle != null:
return idle(_that);case _ADDeleting() when deleting != null:
return deleting(_that);case _ADDone() when done != null:
return done(_that);case _ADFailed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  deleting,TResult Function()?  done,TResult Function( String reason)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ADIdle() when idle != null:
return idle();case _ADDeleting() when deleting != null:
return deleting();case _ADDone() when done != null:
return done();case _ADFailed() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  deleting,required TResult Function()  done,required TResult Function( String reason)  failed,}) {final _that = this;
switch (_that) {
case _ADIdle():
return idle();case _ADDeleting():
return deleting();case _ADDone():
return done();case _ADFailed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  deleting,TResult? Function()?  done,TResult? Function( String reason)?  failed,}) {final _that = this;
switch (_that) {
case _ADIdle() when idle != null:
return idle();case _ADDeleting() when deleting != null:
return deleting();case _ADDone() when done != null:
return done();case _ADFailed() when failed != null:
return failed(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _ADIdle implements AccountDeletionState {
  const _ADIdle();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ADIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AccountDeletionState.idle()';
}


}




/// @nodoc


class _ADDeleting implements AccountDeletionState {
  const _ADDeleting();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ADDeleting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AccountDeletionState.deleting()';
}


}




/// @nodoc


class _ADDone implements AccountDeletionState {
  const _ADDone();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ADDone);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AccountDeletionState.done()';
}


}




/// @nodoc


class _ADFailed implements AccountDeletionState {
  const _ADFailed({required this.reason});
  

 final  String reason;

/// Create a copy of AccountDeletionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ADFailedCopyWith<_ADFailed> get copyWith => __$ADFailedCopyWithImpl<_ADFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ADFailed&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'AccountDeletionState.failed(reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$ADFailedCopyWith<$Res> implements $AccountDeletionStateCopyWith<$Res> {
  factory _$ADFailedCopyWith(_ADFailed value, $Res Function(_ADFailed) _then) = __$ADFailedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class __$ADFailedCopyWithImpl<$Res>
    implements _$ADFailedCopyWith<$Res> {
  __$ADFailedCopyWithImpl(this._self, this._then);

  final _ADFailed _self;
  final $Res Function(_ADFailed) _then;

/// Create a copy of AccountDeletionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(_ADFailed(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
