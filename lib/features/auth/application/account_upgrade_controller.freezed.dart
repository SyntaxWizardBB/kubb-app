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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _UpgradeIdle value)?  idle,TResult Function( _UpgradeLaunching value)?  launching,TResult Function( _UpgradeAwaitingCallback value)?  awaitingCallback,TResult Function( _UpgradeReconciling value)?  reconciling,TResult Function( _UpgradeDone value)?  done,TResult Function( _UpgradeFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpgradeIdle() when idle != null:
return idle(_that);case _UpgradeLaunching() when launching != null:
return launching(_that);case _UpgradeAwaitingCallback() when awaitingCallback != null:
return awaitingCallback(_that);case _UpgradeReconciling() when reconciling != null:
return reconciling(_that);case _UpgradeDone() when done != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _UpgradeIdle value)  idle,required TResult Function( _UpgradeLaunching value)  launching,required TResult Function( _UpgradeAwaitingCallback value)  awaitingCallback,required TResult Function( _UpgradeReconciling value)  reconciling,required TResult Function( _UpgradeDone value)  done,required TResult Function( _UpgradeFailed value)  failed,}){
final _that = this;
switch (_that) {
case _UpgradeIdle():
return idle(_that);case _UpgradeLaunching():
return launching(_that);case _UpgradeAwaitingCallback():
return awaitingCallback(_that);case _UpgradeReconciling():
return reconciling(_that);case _UpgradeDone():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _UpgradeIdle value)?  idle,TResult? Function( _UpgradeLaunching value)?  launching,TResult? Function( _UpgradeAwaitingCallback value)?  awaitingCallback,TResult? Function( _UpgradeReconciling value)?  reconciling,TResult? Function( _UpgradeDone value)?  done,TResult? Function( _UpgradeFailed value)?  failed,}){
final _that = this;
switch (_that) {
case _UpgradeIdle() when idle != null:
return idle(_that);case _UpgradeLaunching() when launching != null:
return launching(_that);case _UpgradeAwaitingCallback() when awaitingCallback != null:
return awaitingCallback(_that);case _UpgradeReconciling() when reconciling != null:
return reconciling(_that);case _UpgradeDone() when done != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( AuthProvider provider)?  launching,TResult Function( AuthProvider provider)?  awaitingCallback,TResult Function( AuthProvider provider)?  reconciling,TResult Function()?  done,TResult Function( String code,  AuthProvider? provider)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpgradeIdle() when idle != null:
return idle();case _UpgradeLaunching() when launching != null:
return launching(_that.provider);case _UpgradeAwaitingCallback() when awaitingCallback != null:
return awaitingCallback(_that.provider);case _UpgradeReconciling() when reconciling != null:
return reconciling(_that.provider);case _UpgradeDone() when done != null:
return done();case _UpgradeFailed() when failed != null:
return failed(_that.code,_that.provider);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( AuthProvider provider)  launching,required TResult Function( AuthProvider provider)  awaitingCallback,required TResult Function( AuthProvider provider)  reconciling,required TResult Function()  done,required TResult Function( String code,  AuthProvider? provider)  failed,}) {final _that = this;
switch (_that) {
case _UpgradeIdle():
return idle();case _UpgradeLaunching():
return launching(_that.provider);case _UpgradeAwaitingCallback():
return awaitingCallback(_that.provider);case _UpgradeReconciling():
return reconciling(_that.provider);case _UpgradeDone():
return done();case _UpgradeFailed():
return failed(_that.code,_that.provider);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( AuthProvider provider)?  launching,TResult? Function( AuthProvider provider)?  awaitingCallback,TResult? Function( AuthProvider provider)?  reconciling,TResult? Function()?  done,TResult? Function( String code,  AuthProvider? provider)?  failed,}) {final _that = this;
switch (_that) {
case _UpgradeIdle() when idle != null:
return idle();case _UpgradeLaunching() when launching != null:
return launching(_that.provider);case _UpgradeAwaitingCallback() when awaitingCallback != null:
return awaitingCallback(_that.provider);case _UpgradeReconciling() when reconciling != null:
return reconciling(_that.provider);case _UpgradeDone() when done != null:
return done();case _UpgradeFailed() when failed != null:
return failed(_that.code,_that.provider);case _:
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


class _UpgradeLaunching implements AccountUpgradeState {
  const _UpgradeLaunching(this.provider);
  

 final  AuthProvider provider;

/// Create a copy of AccountUpgradeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpgradeLaunchingCopyWith<_UpgradeLaunching> get copyWith => __$UpgradeLaunchingCopyWithImpl<_UpgradeLaunching>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpgradeLaunching&&(identical(other.provider, provider) || other.provider == provider));
}


@override
int get hashCode => Object.hash(runtimeType,provider);

@override
String toString() {
  return 'AccountUpgradeState.launching(provider: $provider)';
}


}

/// @nodoc
abstract mixin class _$UpgradeLaunchingCopyWith<$Res> implements $AccountUpgradeStateCopyWith<$Res> {
  factory _$UpgradeLaunchingCopyWith(_UpgradeLaunching value, $Res Function(_UpgradeLaunching) _then) = __$UpgradeLaunchingCopyWithImpl;
@useResult
$Res call({
 AuthProvider provider
});




}
/// @nodoc
class __$UpgradeLaunchingCopyWithImpl<$Res>
    implements _$UpgradeLaunchingCopyWith<$Res> {
  __$UpgradeLaunchingCopyWithImpl(this._self, this._then);

  final _UpgradeLaunching _self;
  final $Res Function(_UpgradeLaunching) _then;

/// Create a copy of AccountUpgradeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? provider = null,}) {
  return _then(_UpgradeLaunching(
null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AuthProvider,
  ));
}


}

/// @nodoc


class _UpgradeAwaitingCallback implements AccountUpgradeState {
  const _UpgradeAwaitingCallback(this.provider);
  

 final  AuthProvider provider;

/// Create a copy of AccountUpgradeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpgradeAwaitingCallbackCopyWith<_UpgradeAwaitingCallback> get copyWith => __$UpgradeAwaitingCallbackCopyWithImpl<_UpgradeAwaitingCallback>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpgradeAwaitingCallback&&(identical(other.provider, provider) || other.provider == provider));
}


@override
int get hashCode => Object.hash(runtimeType,provider);

@override
String toString() {
  return 'AccountUpgradeState.awaitingCallback(provider: $provider)';
}


}

/// @nodoc
abstract mixin class _$UpgradeAwaitingCallbackCopyWith<$Res> implements $AccountUpgradeStateCopyWith<$Res> {
  factory _$UpgradeAwaitingCallbackCopyWith(_UpgradeAwaitingCallback value, $Res Function(_UpgradeAwaitingCallback) _then) = __$UpgradeAwaitingCallbackCopyWithImpl;
@useResult
$Res call({
 AuthProvider provider
});




}
/// @nodoc
class __$UpgradeAwaitingCallbackCopyWithImpl<$Res>
    implements _$UpgradeAwaitingCallbackCopyWith<$Res> {
  __$UpgradeAwaitingCallbackCopyWithImpl(this._self, this._then);

  final _UpgradeAwaitingCallback _self;
  final $Res Function(_UpgradeAwaitingCallback) _then;

/// Create a copy of AccountUpgradeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? provider = null,}) {
  return _then(_UpgradeAwaitingCallback(
null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AuthProvider,
  ));
}


}

/// @nodoc


class _UpgradeReconciling implements AccountUpgradeState {
  const _UpgradeReconciling(this.provider);
  

 final  AuthProvider provider;

/// Create a copy of AccountUpgradeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpgradeReconcilingCopyWith<_UpgradeReconciling> get copyWith => __$UpgradeReconcilingCopyWithImpl<_UpgradeReconciling>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpgradeReconciling&&(identical(other.provider, provider) || other.provider == provider));
}


@override
int get hashCode => Object.hash(runtimeType,provider);

@override
String toString() {
  return 'AccountUpgradeState.reconciling(provider: $provider)';
}


}

/// @nodoc
abstract mixin class _$UpgradeReconcilingCopyWith<$Res> implements $AccountUpgradeStateCopyWith<$Res> {
  factory _$UpgradeReconcilingCopyWith(_UpgradeReconciling value, $Res Function(_UpgradeReconciling) _then) = __$UpgradeReconcilingCopyWithImpl;
@useResult
$Res call({
 AuthProvider provider
});




}
/// @nodoc
class __$UpgradeReconcilingCopyWithImpl<$Res>
    implements _$UpgradeReconcilingCopyWith<$Res> {
  __$UpgradeReconcilingCopyWithImpl(this._self, this._then);

  final _UpgradeReconciling _self;
  final $Res Function(_UpgradeReconciling) _then;

/// Create a copy of AccountUpgradeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? provider = null,}) {
  return _then(_UpgradeReconciling(
null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AuthProvider,
  ));
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
  const _UpgradeFailed({required this.code, this.provider});
  

 final  String code;
 final  AuthProvider? provider;

/// Create a copy of AccountUpgradeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpgradeFailedCopyWith<_UpgradeFailed> get copyWith => __$UpgradeFailedCopyWithImpl<_UpgradeFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpgradeFailed&&(identical(other.code, code) || other.code == code)&&(identical(other.provider, provider) || other.provider == provider));
}


@override
int get hashCode => Object.hash(runtimeType,code,provider);

@override
String toString() {
  return 'AccountUpgradeState.failed(code: $code, provider: $provider)';
}


}

/// @nodoc
abstract mixin class _$UpgradeFailedCopyWith<$Res> implements $AccountUpgradeStateCopyWith<$Res> {
  factory _$UpgradeFailedCopyWith(_UpgradeFailed value, $Res Function(_UpgradeFailed) _then) = __$UpgradeFailedCopyWithImpl;
@useResult
$Res call({
 String code, AuthProvider? provider
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
@pragma('vm:prefer-inline') $Res call({Object? code = null,Object? provider = freezed,}) {
  return _then(_UpgradeFailed(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,provider: freezed == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AuthProvider?,
  ));
}


}

// dart format on
