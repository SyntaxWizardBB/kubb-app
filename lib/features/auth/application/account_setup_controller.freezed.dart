// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account_setup_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountSetupState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountSetupState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AccountSetupState()';
}


}

/// @nodoc
class $AccountSetupStateCopyWith<$Res>  {
$AccountSetupStateCopyWith(AccountSetupState _, $Res Function(AccountSetupState) __);
}


/// Adds pattern-matching-related methods to [AccountSetupState].
extension AccountSetupStatePatterns on AccountSetupState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _Idle value)?  idle,TResult Function( _NicknameEntered value)?  nicknameEntered,TResult Function( _MnemonicReady value)?  mnemonicReady,TResult Function( _Submitting value)?  submitting,TResult Function( _Done value)?  done,TResult Function( _Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Idle() when idle != null:
return idle(_that);case _NicknameEntered() when nicknameEntered != null:
return nicknameEntered(_that);case _MnemonicReady() when mnemonicReady != null:
return mnemonicReady(_that);case _Submitting() when submitting != null:
return submitting(_that);case _Done() when done != null:
return done(_that);case _Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _Idle value)  idle,required TResult Function( _NicknameEntered value)  nicknameEntered,required TResult Function( _MnemonicReady value)  mnemonicReady,required TResult Function( _Submitting value)  submitting,required TResult Function( _Done value)  done,required TResult Function( _Failed value)  failed,}){
final _that = this;
switch (_that) {
case _Idle():
return idle(_that);case _NicknameEntered():
return nicknameEntered(_that);case _MnemonicReady():
return mnemonicReady(_that);case _Submitting():
return submitting(_that);case _Done():
return done(_that);case _Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _Idle value)?  idle,TResult? Function( _NicknameEntered value)?  nicknameEntered,TResult? Function( _MnemonicReady value)?  mnemonicReady,TResult? Function( _Submitting value)?  submitting,TResult? Function( _Done value)?  done,TResult? Function( _Failed value)?  failed,}){
final _that = this;
switch (_that) {
case _Idle() when idle != null:
return idle(_that);case _NicknameEntered() when nicknameEntered != null:
return nicknameEntered(_that);case _MnemonicReady() when mnemonicReady != null:
return mnemonicReady(_that);case _Submitting() when submitting != null:
return submitting(_that);case _Done() when done != null:
return done(_that);case _Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( String nickname)?  nicknameEntered,TResult Function( String nickname,  String mnemonic,  int wordCount)?  mnemonicReady,TResult Function()?  submitting,TResult Function( String userId)?  done,TResult Function( String reason)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Idle() when idle != null:
return idle();case _NicknameEntered() when nicknameEntered != null:
return nicknameEntered(_that.nickname);case _MnemonicReady() when mnemonicReady != null:
return mnemonicReady(_that.nickname,_that.mnemonic,_that.wordCount);case _Submitting() when submitting != null:
return submitting();case _Done() when done != null:
return done(_that.userId);case _Failed() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( String nickname)  nicknameEntered,required TResult Function( String nickname,  String mnemonic,  int wordCount)  mnemonicReady,required TResult Function()  submitting,required TResult Function( String userId)  done,required TResult Function( String reason)  failed,}) {final _that = this;
switch (_that) {
case _Idle():
return idle();case _NicknameEntered():
return nicknameEntered(_that.nickname);case _MnemonicReady():
return mnemonicReady(_that.nickname,_that.mnemonic,_that.wordCount);case _Submitting():
return submitting();case _Done():
return done(_that.userId);case _Failed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( String nickname)?  nicknameEntered,TResult? Function( String nickname,  String mnemonic,  int wordCount)?  mnemonicReady,TResult? Function()?  submitting,TResult? Function( String userId)?  done,TResult? Function( String reason)?  failed,}) {final _that = this;
switch (_that) {
case _Idle() when idle != null:
return idle();case _NicknameEntered() when nicknameEntered != null:
return nicknameEntered(_that.nickname);case _MnemonicReady() when mnemonicReady != null:
return mnemonicReady(_that.nickname,_that.mnemonic,_that.wordCount);case _Submitting() when submitting != null:
return submitting();case _Done() when done != null:
return done(_that.userId);case _Failed() when failed != null:
return failed(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _Idle implements AccountSetupState {
  const _Idle();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Idle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AccountSetupState.idle()';
}


}




/// @nodoc


class _NicknameEntered implements AccountSetupState {
  const _NicknameEntered({required this.nickname});
  

 final  String nickname;

/// Create a copy of AccountSetupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NicknameEnteredCopyWith<_NicknameEntered> get copyWith => __$NicknameEnteredCopyWithImpl<_NicknameEntered>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NicknameEntered&&(identical(other.nickname, nickname) || other.nickname == nickname));
}


@override
int get hashCode => Object.hash(runtimeType,nickname);

@override
String toString() {
  return 'AccountSetupState.nicknameEntered(nickname: $nickname)';
}


}

/// @nodoc
abstract mixin class _$NicknameEnteredCopyWith<$Res> implements $AccountSetupStateCopyWith<$Res> {
  factory _$NicknameEnteredCopyWith(_NicknameEntered value, $Res Function(_NicknameEntered) _then) = __$NicknameEnteredCopyWithImpl;
@useResult
$Res call({
 String nickname
});




}
/// @nodoc
class __$NicknameEnteredCopyWithImpl<$Res>
    implements _$NicknameEnteredCopyWith<$Res> {
  __$NicknameEnteredCopyWithImpl(this._self, this._then);

  final _NicknameEntered _self;
  final $Res Function(_NicknameEntered) _then;

/// Create a copy of AccountSetupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nickname = null,}) {
  return _then(_NicknameEntered(
nickname: null == nickname ? _self.nickname : nickname // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class _MnemonicReady implements AccountSetupState {
  const _MnemonicReady({required this.nickname, required this.mnemonic, required this.wordCount});
  

 final  String nickname;
 final  String mnemonic;
 final  int wordCount;

/// Create a copy of AccountSetupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MnemonicReadyCopyWith<_MnemonicReady> get copyWith => __$MnemonicReadyCopyWithImpl<_MnemonicReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MnemonicReady&&(identical(other.nickname, nickname) || other.nickname == nickname)&&(identical(other.mnemonic, mnemonic) || other.mnemonic == mnemonic)&&(identical(other.wordCount, wordCount) || other.wordCount == wordCount));
}


@override
int get hashCode => Object.hash(runtimeType,nickname,mnemonic,wordCount);

@override
String toString() {
  return 'AccountSetupState.mnemonicReady(nickname: $nickname, mnemonic: $mnemonic, wordCount: $wordCount)';
}


}

/// @nodoc
abstract mixin class _$MnemonicReadyCopyWith<$Res> implements $AccountSetupStateCopyWith<$Res> {
  factory _$MnemonicReadyCopyWith(_MnemonicReady value, $Res Function(_MnemonicReady) _then) = __$MnemonicReadyCopyWithImpl;
@useResult
$Res call({
 String nickname, String mnemonic, int wordCount
});




}
/// @nodoc
class __$MnemonicReadyCopyWithImpl<$Res>
    implements _$MnemonicReadyCopyWith<$Res> {
  __$MnemonicReadyCopyWithImpl(this._self, this._then);

  final _MnemonicReady _self;
  final $Res Function(_MnemonicReady) _then;

/// Create a copy of AccountSetupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nickname = null,Object? mnemonic = null,Object? wordCount = null,}) {
  return _then(_MnemonicReady(
nickname: null == nickname ? _self.nickname : nickname // ignore: cast_nullable_to_non_nullable
as String,mnemonic: null == mnemonic ? _self.mnemonic : mnemonic // ignore: cast_nullable_to_non_nullable
as String,wordCount: null == wordCount ? _self.wordCount : wordCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class _Submitting implements AccountSetupState {
  const _Submitting();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Submitting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AccountSetupState.submitting()';
}


}




/// @nodoc


class _Done implements AccountSetupState {
  const _Done({required this.userId});
  

 final  String userId;

/// Create a copy of AccountSetupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DoneCopyWith<_Done> get copyWith => __$DoneCopyWithImpl<_Done>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Done&&(identical(other.userId, userId) || other.userId == userId));
}


@override
int get hashCode => Object.hash(runtimeType,userId);

@override
String toString() {
  return 'AccountSetupState.done(userId: $userId)';
}


}

/// @nodoc
abstract mixin class _$DoneCopyWith<$Res> implements $AccountSetupStateCopyWith<$Res> {
  factory _$DoneCopyWith(_Done value, $Res Function(_Done) _then) = __$DoneCopyWithImpl;
@useResult
$Res call({
 String userId
});




}
/// @nodoc
class __$DoneCopyWithImpl<$Res>
    implements _$DoneCopyWith<$Res> {
  __$DoneCopyWithImpl(this._self, this._then);

  final _Done _self;
  final $Res Function(_Done) _then;

/// Create a copy of AccountSetupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,}) {
  return _then(_Done(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class _Failed implements AccountSetupState {
  const _Failed({required this.reason});
  

 final  String reason;

/// Create a copy of AccountSetupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FailedCopyWith<_Failed> get copyWith => __$FailedCopyWithImpl<_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Failed&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'AccountSetupState.failed(reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$FailedCopyWith<$Res> implements $AccountSetupStateCopyWith<$Res> {
  factory _$FailedCopyWith(_Failed value, $Res Function(_Failed) _then) = __$FailedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class __$FailedCopyWithImpl<$Res>
    implements _$FailedCopyWith<$Res> {
  __$FailedCopyWithImpl(this._self, this._then);

  final _Failed _self;
  final $Res Function(_Failed) _then;

/// Create a copy of AccountSetupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(_Failed(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
