// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AppSettings {

 ThemeChoice get themeChoice; bool get heliTracking; bool get vibration; bool get sniperEyeToggleHidden; bool get longDubbieTracking; bool get penaltyKubbTracking; bool get kingThrowTracking; bool get allowContinueBeyondSticks;
/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppSettingsCopyWith<AppSettings> get copyWith => _$AppSettingsCopyWithImpl<AppSettings>(this as AppSettings, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppSettings&&(identical(other.themeChoice, themeChoice) || other.themeChoice == themeChoice)&&(identical(other.heliTracking, heliTracking) || other.heliTracking == heliTracking)&&(identical(other.vibration, vibration) || other.vibration == vibration)&&(identical(other.sniperEyeToggleHidden, sniperEyeToggleHidden) || other.sniperEyeToggleHidden == sniperEyeToggleHidden)&&(identical(other.longDubbieTracking, longDubbieTracking) || other.longDubbieTracking == longDubbieTracking)&&(identical(other.penaltyKubbTracking, penaltyKubbTracking) || other.penaltyKubbTracking == penaltyKubbTracking)&&(identical(other.kingThrowTracking, kingThrowTracking) || other.kingThrowTracking == kingThrowTracking)&&(identical(other.allowContinueBeyondSticks, allowContinueBeyondSticks) || other.allowContinueBeyondSticks == allowContinueBeyondSticks));
}


@override
int get hashCode => Object.hash(runtimeType,themeChoice,heliTracking,vibration,sniperEyeToggleHidden,longDubbieTracking,penaltyKubbTracking,kingThrowTracking,allowContinueBeyondSticks);

@override
String toString() {
  return 'AppSettings(themeChoice: $themeChoice, heliTracking: $heliTracking, vibration: $vibration, sniperEyeToggleHidden: $sniperEyeToggleHidden, longDubbieTracking: $longDubbieTracking, penaltyKubbTracking: $penaltyKubbTracking, kingThrowTracking: $kingThrowTracking, allowContinueBeyondSticks: $allowContinueBeyondSticks)';
}


}

/// @nodoc
abstract mixin class $AppSettingsCopyWith<$Res>  {
  factory $AppSettingsCopyWith(AppSettings value, $Res Function(AppSettings) _then) = _$AppSettingsCopyWithImpl;
@useResult
$Res call({
 ThemeChoice themeChoice, bool heliTracking, bool vibration, bool sniperEyeToggleHidden, bool longDubbieTracking, bool penaltyKubbTracking, bool kingThrowTracking, bool allowContinueBeyondSticks
});




}
/// @nodoc
class _$AppSettingsCopyWithImpl<$Res>
    implements $AppSettingsCopyWith<$Res> {
  _$AppSettingsCopyWithImpl(this._self, this._then);

  final AppSettings _self;
  final $Res Function(AppSettings) _then;

/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? themeChoice = null,Object? heliTracking = null,Object? vibration = null,Object? sniperEyeToggleHidden = null,Object? longDubbieTracking = null,Object? penaltyKubbTracking = null,Object? kingThrowTracking = null,Object? allowContinueBeyondSticks = null,}) {
  return _then(_self.copyWith(
themeChoice: null == themeChoice ? _self.themeChoice : themeChoice // ignore: cast_nullable_to_non_nullable
as ThemeChoice,heliTracking: null == heliTracking ? _self.heliTracking : heliTracking // ignore: cast_nullable_to_non_nullable
as bool,vibration: null == vibration ? _self.vibration : vibration // ignore: cast_nullable_to_non_nullable
as bool,sniperEyeToggleHidden: null == sniperEyeToggleHidden ? _self.sniperEyeToggleHidden : sniperEyeToggleHidden // ignore: cast_nullable_to_non_nullable
as bool,longDubbieTracking: null == longDubbieTracking ? _self.longDubbieTracking : longDubbieTracking // ignore: cast_nullable_to_non_nullable
as bool,penaltyKubbTracking: null == penaltyKubbTracking ? _self.penaltyKubbTracking : penaltyKubbTracking // ignore: cast_nullable_to_non_nullable
as bool,kingThrowTracking: null == kingThrowTracking ? _self.kingThrowTracking : kingThrowTracking // ignore: cast_nullable_to_non_nullable
as bool,allowContinueBeyondSticks: null == allowContinueBeyondSticks ? _self.allowContinueBeyondSticks : allowContinueBeyondSticks // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [AppSettings].
extension AppSettingsPatterns on AppSettings {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AppSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AppSettings value)  $default,){
final _that = this;
switch (_that) {
case _AppSettings():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AppSettings value)?  $default,){
final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThemeChoice themeChoice,  bool heliTracking,  bool vibration,  bool sniperEyeToggleHidden,  bool longDubbieTracking,  bool penaltyKubbTracking,  bool kingThrowTracking,  bool allowContinueBeyondSticks)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.themeChoice,_that.heliTracking,_that.vibration,_that.sniperEyeToggleHidden,_that.longDubbieTracking,_that.penaltyKubbTracking,_that.kingThrowTracking,_that.allowContinueBeyondSticks);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThemeChoice themeChoice,  bool heliTracking,  bool vibration,  bool sniperEyeToggleHidden,  bool longDubbieTracking,  bool penaltyKubbTracking,  bool kingThrowTracking,  bool allowContinueBeyondSticks)  $default,) {final _that = this;
switch (_that) {
case _AppSettings():
return $default(_that.themeChoice,_that.heliTracking,_that.vibration,_that.sniperEyeToggleHidden,_that.longDubbieTracking,_that.penaltyKubbTracking,_that.kingThrowTracking,_that.allowContinueBeyondSticks);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThemeChoice themeChoice,  bool heliTracking,  bool vibration,  bool sniperEyeToggleHidden,  bool longDubbieTracking,  bool penaltyKubbTracking,  bool kingThrowTracking,  bool allowContinueBeyondSticks)?  $default,) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.themeChoice,_that.heliTracking,_that.vibration,_that.sniperEyeToggleHidden,_that.longDubbieTracking,_that.penaltyKubbTracking,_that.kingThrowTracking,_that.allowContinueBeyondSticks);case _:
  return null;

}
}

}

/// @nodoc


class _AppSettings extends AppSettings {
  const _AppSettings({this.themeChoice = ThemeChoice.light, this.heliTracking = true, this.vibration = true, this.sniperEyeToggleHidden = false, this.longDubbieTracking = true, this.penaltyKubbTracking = true, this.kingThrowTracking = true, this.allowContinueBeyondSticks = true}): super._();
  

@override@JsonKey() final  ThemeChoice themeChoice;
@override@JsonKey() final  bool heliTracking;
@override@JsonKey() final  bool vibration;
@override@JsonKey() final  bool sniperEyeToggleHidden;
@override@JsonKey() final  bool longDubbieTracking;
@override@JsonKey() final  bool penaltyKubbTracking;
@override@JsonKey() final  bool kingThrowTracking;
@override@JsonKey() final  bool allowContinueBeyondSticks;

/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppSettingsCopyWith<_AppSettings> get copyWith => __$AppSettingsCopyWithImpl<_AppSettings>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppSettings&&(identical(other.themeChoice, themeChoice) || other.themeChoice == themeChoice)&&(identical(other.heliTracking, heliTracking) || other.heliTracking == heliTracking)&&(identical(other.vibration, vibration) || other.vibration == vibration)&&(identical(other.sniperEyeToggleHidden, sniperEyeToggleHidden) || other.sniperEyeToggleHidden == sniperEyeToggleHidden)&&(identical(other.longDubbieTracking, longDubbieTracking) || other.longDubbieTracking == longDubbieTracking)&&(identical(other.penaltyKubbTracking, penaltyKubbTracking) || other.penaltyKubbTracking == penaltyKubbTracking)&&(identical(other.kingThrowTracking, kingThrowTracking) || other.kingThrowTracking == kingThrowTracking)&&(identical(other.allowContinueBeyondSticks, allowContinueBeyondSticks) || other.allowContinueBeyondSticks == allowContinueBeyondSticks));
}


@override
int get hashCode => Object.hash(runtimeType,themeChoice,heliTracking,vibration,sniperEyeToggleHidden,longDubbieTracking,penaltyKubbTracking,kingThrowTracking,allowContinueBeyondSticks);

@override
String toString() {
  return 'AppSettings(themeChoice: $themeChoice, heliTracking: $heliTracking, vibration: $vibration, sniperEyeToggleHidden: $sniperEyeToggleHidden, longDubbieTracking: $longDubbieTracking, penaltyKubbTracking: $penaltyKubbTracking, kingThrowTracking: $kingThrowTracking, allowContinueBeyondSticks: $allowContinueBeyondSticks)';
}


}

/// @nodoc
abstract mixin class _$AppSettingsCopyWith<$Res> implements $AppSettingsCopyWith<$Res> {
  factory _$AppSettingsCopyWith(_AppSettings value, $Res Function(_AppSettings) _then) = __$AppSettingsCopyWithImpl;
@override @useResult
$Res call({
 ThemeChoice themeChoice, bool heliTracking, bool vibration, bool sniperEyeToggleHidden, bool longDubbieTracking, bool penaltyKubbTracking, bool kingThrowTracking, bool allowContinueBeyondSticks
});




}
/// @nodoc
class __$AppSettingsCopyWithImpl<$Res>
    implements _$AppSettingsCopyWith<$Res> {
  __$AppSettingsCopyWithImpl(this._self, this._then);

  final _AppSettings _self;
  final $Res Function(_AppSettings) _then;

/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? themeChoice = null,Object? heliTracking = null,Object? vibration = null,Object? sniperEyeToggleHidden = null,Object? longDubbieTracking = null,Object? penaltyKubbTracking = null,Object? kingThrowTracking = null,Object? allowContinueBeyondSticks = null,}) {
  return _then(_AppSettings(
themeChoice: null == themeChoice ? _self.themeChoice : themeChoice // ignore: cast_nullable_to_non_nullable
as ThemeChoice,heliTracking: null == heliTracking ? _self.heliTracking : heliTracking // ignore: cast_nullable_to_non_nullable
as bool,vibration: null == vibration ? _self.vibration : vibration // ignore: cast_nullable_to_non_nullable
as bool,sniperEyeToggleHidden: null == sniperEyeToggleHidden ? _self.sniperEyeToggleHidden : sniperEyeToggleHidden // ignore: cast_nullable_to_non_nullable
as bool,longDubbieTracking: null == longDubbieTracking ? _self.longDubbieTracking : longDubbieTracking // ignore: cast_nullable_to_non_nullable
as bool,penaltyKubbTracking: null == penaltyKubbTracking ? _self.penaltyKubbTracking : penaltyKubbTracking // ignore: cast_nullable_to_non_nullable
as bool,kingThrowTracking: null == kingThrowTracking ? _self.kingThrowTracking : kingThrowTracking // ignore: cast_nullable_to_non_nullable
as bool,allowContinueBeyondSticks: null == allowContinueBeyondSticks ? _self.allowContinueBeyondSticks : allowContinueBeyondSticks // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
