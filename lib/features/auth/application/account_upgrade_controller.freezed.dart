// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account_upgrade_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountUpgradeState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUpgradeState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AccountUpgradeState()';
}


}

/// @nodoc
class $AccountUpgradeStateCopyWith<$Res>  {
$AccountUpgradeStateCopyWith(AccountUpgradeState _, $Res Function(AccountUpgradeState) __);
}


/// Adds pattern-matching-related methods to [AccountUpgradeState].
extension AccountUpgradeStatePatterns on AccountUpgradeState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _UpgradeIdle value)?  idle,TResult Function( _UpgradeLinking value)?  linking,TResult Function( _UpgradeDone value)?  done,TResult Function( _UpgradeFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpgradeIdle() when idle != null:
return idle(_that);case _UpgradeLinking() when linking != null:
return linking(_that);case _UpgradeDone() when done != null:
return done(_that);case _UpgradeFailed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _UpgradeIdle value)  idle,required TResult Function( _UpgradeLinking value)  linking,required TResult Function( _UpgradeDone value)  done,required TResult Function( _UpgradeFailed value)  failed,}){
final _that = this;
switch (_that) {
case _UpgradeIdle():
return idle(_that);case _UpgradeLinking():
return linking(_that);case _UpgradeDone():
return done(_that);case _UpgradeFailed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _UpgradeIdle value)?  idle,TResult? Function( _UpgradeLinking value)?  linking,TResult? Function( _UpgradeDone value)?  done,TResult? Function( _UpgradeFailed value)?  failed,}){
final _that = this;
switch (_that) {
case _UpgradeIdle() when idle != null:
return idle(_that);case _UpgradeLinking() when linking != null:
return linking(_that);case _UpgradeDone() when done != null:
return done(_that);case _UpgradeFailed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  linking,TResult Function()?  done,TResult Function( String reason)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpgradeIdle() when idle != null:
return idle();case _UpgradeLinking() when linking != null:
return linking();case _UpgradeDone() when done != null:
return done();case _UpgradeFailed() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  linking,required TResult Function()  done,required TResult Function( String reason)  failed,}) {final _that = this;
switch (_that) {
case _UpgradeIdle():
return idle();case _UpgradeLinking():
return linking();case _UpgradeDone():
return done();case _UpgradeFailed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  linking,TResult? Function()?  done,TResult? Function( String reason)?  failed,}) {final _that = this;
switch (_that) {
case _UpgradeIdle() when idle != null:
return idle();case _UpgradeLinking() when linking != null:
return linking();case _UpgradeDone() when done != null:
return done();case _UpgradeFailed() when failed != null:
return failed(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _UpgradeIdle implements AccountUpgradeState {
  const _UpgradeIdle();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpgradeIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AccountUpgradeState.idle()';
}


}




/// @nodoc


class _UpgradeLinking implements AccountUpgradeState {
  const _UpgradeLinking();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpgradeLinking);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AccountUpgradeState.linking()';
}


}




/// @nodoc


class _UpgradeDone implements AccountUpgradeState {
  const _UpgradeDone();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpgradeDone);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AccountUpgradeState.done()';
}


}




/// @nodoc


class _UpgradeFailed implements AccountUpgradeState {
  const _UpgradeFailed({required this.reason});
  

 final  String reason;

/// Create a copy of AccountUpgradeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpgradeFailedCopyWith<_UpgradeFailed> get copyWith => __$UpgradeFailedCopyWithImpl<_UpgradeFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpgradeFailed&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'AccountUpgradeState.failed(reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$UpgradeFailedCopyWith<$Res> implements $AccountUpgradeStateCopyWith<$Res> {
  factory _$UpgradeFailedCopyWith(_UpgradeFailed value, $Res Function(_UpgradeFailed) _then) = __$UpgradeFailedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class __$UpgradeFailedCopyWithImpl<$Res>
    implements _$UpgradeFailedCopyWith<$Res> {
  __$UpgradeFailedCopyWithImpl(this._self, this._then);

  final _UpgradeFailed _self;
  final $Res Function(_UpgradeFailed) _then;

/// Create a copy of AccountUpgradeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(_UpgradeFailed(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
