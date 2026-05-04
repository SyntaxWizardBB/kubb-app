// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'passphrase_change_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PassphraseChangeState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PassphraseChangeState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PassphraseChangeState()';
}


}

/// @nodoc
class $PassphraseChangeStateCopyWith<$Res>  {
$PassphraseChangeStateCopyWith(PassphraseChangeState _, $Res Function(PassphraseChangeState) __);
}


/// Adds pattern-matching-related methods to [PassphraseChangeState].
extension PassphraseChangeStatePatterns on PassphraseChangeState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _PCIdle value)?  idle,TResult Function( _PCChanging value)?  changing,TResult Function( _PCDone value)?  done,TResult Function( _PCFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PCIdle() when idle != null:
return idle(_that);case _PCChanging() when changing != null:
return changing(_that);case _PCDone() when done != null:
return done(_that);case _PCFailed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _PCIdle value)  idle,required TResult Function( _PCChanging value)  changing,required TResult Function( _PCDone value)  done,required TResult Function( _PCFailed value)  failed,}){
final _that = this;
switch (_that) {
case _PCIdle():
return idle(_that);case _PCChanging():
return changing(_that);case _PCDone():
return done(_that);case _PCFailed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _PCIdle value)?  idle,TResult? Function( _PCChanging value)?  changing,TResult? Function( _PCDone value)?  done,TResult? Function( _PCFailed value)?  failed,}){
final _that = this;
switch (_that) {
case _PCIdle() when idle != null:
return idle(_that);case _PCChanging() when changing != null:
return changing(_that);case _PCDone() when done != null:
return done(_that);case _PCFailed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  changing,TResult Function()?  done,TResult Function( String reason)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PCIdle() when idle != null:
return idle();case _PCChanging() when changing != null:
return changing();case _PCDone() when done != null:
return done();case _PCFailed() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  changing,required TResult Function()  done,required TResult Function( String reason)  failed,}) {final _that = this;
switch (_that) {
case _PCIdle():
return idle();case _PCChanging():
return changing();case _PCDone():
return done();case _PCFailed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  changing,TResult? Function()?  done,TResult? Function( String reason)?  failed,}) {final _that = this;
switch (_that) {
case _PCIdle() when idle != null:
return idle();case _PCChanging() when changing != null:
return changing();case _PCDone() when done != null:
return done();case _PCFailed() when failed != null:
return failed(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _PCIdle implements PassphraseChangeState {
  const _PCIdle();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PCIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PassphraseChangeState.idle()';
}


}




/// @nodoc


class _PCChanging implements PassphraseChangeState {
  const _PCChanging();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PCChanging);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PassphraseChangeState.changing()';
}


}




/// @nodoc


class _PCDone implements PassphraseChangeState {
  const _PCDone();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PCDone);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PassphraseChangeState.done()';
}


}




/// @nodoc


class _PCFailed implements PassphraseChangeState {
  const _PCFailed({required this.reason});
  

 final  String reason;

/// Create a copy of PassphraseChangeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PCFailedCopyWith<_PCFailed> get copyWith => __$PCFailedCopyWithImpl<_PCFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PCFailed&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'PassphraseChangeState.failed(reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$PCFailedCopyWith<$Res> implements $PassphraseChangeStateCopyWith<$Res> {
  factory _$PCFailedCopyWith(_PCFailed value, $Res Function(_PCFailed) _then) = __$PCFailedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class __$PCFailedCopyWithImpl<$Res>
    implements _$PCFailedCopyWith<$Res> {
  __$PCFailedCopyWithImpl(this._self, this._then);

  final _PCFailed _self;
  final $Res Function(_PCFailed) _then;

/// Create a copy of PassphraseChangeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(_PCFailed(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
