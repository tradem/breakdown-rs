// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'setup_wizard_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BlockDraft {

/// Episodes per block; the smart default (team decision: default small
/// — the reference templates use 6/8).
 int get episodeCount;/// Optional block title; empty means "no title" (the backend titles
/// blocks by number).
 String get title;
/// Create a copy of BlockDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlockDraftCopyWith<BlockDraft> get copyWith => _$BlockDraftCopyWithImpl<BlockDraft>(this as BlockDraft, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BlockDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockDraft&&(identical(other.episodeCount, _this.episodeCount) || other.episodeCount == _this.episodeCount)&&(identical(other.title, _this.title) || other.title == _this.title));
}


@override
int get hashCode {
  final _this = this as BlockDraft;
  return Object.hash(runtimeType,_this.episodeCount,_this.title);
}

@override
String toString() {
  final _this = this as BlockDraft;
  return 'BlockDraft(episodeCount: ${_this.episodeCount}, title: ${_this.title})';
}


}

/// @nodoc
abstract mixin class $BlockDraftCopyWith<$Res>  {
  factory $BlockDraftCopyWith(BlockDraft value, $Res Function(BlockDraft) _then) = _$BlockDraftCopyWithImpl;
@useResult
$Res call({
 int episodeCount, String title
});




}
/// @nodoc
class _$BlockDraftCopyWithImpl<$Res>
    implements $BlockDraftCopyWith<$Res> {
  _$BlockDraftCopyWithImpl(this._self, this._then);

  final BlockDraft _self;
  final $Res Function(BlockDraft) _then;

/// Create a copy of BlockDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? episodeCount = null,Object? title = null,}) {
  return _then(BlockDraft(
episodeCount: null == episodeCount ? _self.episodeCount : episodeCount // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BlockDraft].
extension BlockDraftPatterns on BlockDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BlockDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BlockDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BlockDraft value)  $default,){
final _that = this;
switch (_that) {
case _BlockDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BlockDraft value)?  $default,){
final _that = this;
switch (_that) {
case _BlockDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int episodeCount,  String title)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BlockDraft() when $default != null:
return $default(_that.episodeCount,_that.title);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int episodeCount,  String title)  $default,) {final _that = this;
switch (_that) {
case _BlockDraft():
return $default(_that.episodeCount,_that.title);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int episodeCount,  String title)?  $default,) {final _that = this;
switch (_that) {
case _BlockDraft() when $default != null:
return $default(_that.episodeCount,_that.title);case _:
  return null;

}
}

}

/// @nodoc


class _BlockDraft extends BlockDraft {
  const _BlockDraft({this.episodeCount = 8, this.title = ''}): super._();
  

/// Episodes per block; the smart default (team decision: default small
/// — the reference templates use 6/8).
@override@JsonKey() final  int episodeCount;
/// Optional block title; empty means "no title" (the backend titles
/// blocks by number).
@override@JsonKey() final  String title;

/// Create a copy of BlockDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BlockDraftCopyWith<_BlockDraft> get copyWith => __$BlockDraftCopyWithImpl<_BlockDraft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BlockDraft&&(identical(other.episodeCount, episodeCount) || other.episodeCount == episodeCount)&&(identical(other.title, title) || other.title == title));
}


@override
int get hashCode {
    return Object.hash(runtimeType,episodeCount,title);
}

@override
String toString() {
    return 'BlockDraft(episodeCount: $episodeCount, title: $title)';
}


}

/// @nodoc
abstract mixin class _$BlockDraftCopyWith<$Res> implements $BlockDraftCopyWith<$Res> {
  factory _$BlockDraftCopyWith(_BlockDraft value, $Res Function(_BlockDraft) _then) = __$BlockDraftCopyWithImpl;
@override @useResult
$Res call({
 int episodeCount, String title
});




}
/// @nodoc
class __$BlockDraftCopyWithImpl<$Res>
    implements _$BlockDraftCopyWith<$Res> {
  __$BlockDraftCopyWithImpl(this._self, this._then);

  final _BlockDraft _self;
  final $Res Function(_BlockDraft) _then;

/// Create a copy of BlockDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? episodeCount = null,Object? title = null,}) {
  return _then(_BlockDraft(
episodeCount: null == episodeCount ? _self.episodeCount : episodeCount // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$WizardCreatedSeason {

 String get id; int get number; String get title;
/// Create a copy of WizardCreatedSeason
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WizardCreatedSeasonCopyWith<WizardCreatedSeason> get copyWith => _$WizardCreatedSeasonCopyWithImpl<WizardCreatedSeason>(this as WizardCreatedSeason, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WizardCreatedSeason;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WizardCreatedSeason&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.number, _this.number) || other.number == _this.number)&&(identical(other.title, _this.title) || other.title == _this.title));
}


@override
int get hashCode {
  final _this = this as WizardCreatedSeason;
  return Object.hash(runtimeType,_this.id,_this.number,_this.title);
}

@override
String toString() {
  final _this = this as WizardCreatedSeason;
  return 'WizardCreatedSeason(id: ${_this.id}, number: ${_this.number}, title: ${_this.title})';
}


}

/// @nodoc
abstract mixin class $WizardCreatedSeasonCopyWith<$Res>  {
  factory $WizardCreatedSeasonCopyWith(WizardCreatedSeason value, $Res Function(WizardCreatedSeason) _then) = _$WizardCreatedSeasonCopyWithImpl;
@useResult
$Res call({
 String id, int number, String title
});




}
/// @nodoc
class _$WizardCreatedSeasonCopyWithImpl<$Res>
    implements $WizardCreatedSeasonCopyWith<$Res> {
  _$WizardCreatedSeasonCopyWithImpl(this._self, this._then);

  final WizardCreatedSeason _self;
  final $Res Function(WizardCreatedSeason) _then;

/// Create a copy of WizardCreatedSeason
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? number = null,Object? title = null,}) {
  return _then(WizardCreatedSeason(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,number: null == number ? _self.number : number // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [WizardCreatedSeason].
extension WizardCreatedSeasonPatterns on WizardCreatedSeason {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WizardCreatedSeason value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WizardCreatedSeason() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WizardCreatedSeason value)  $default,){
final _that = this;
switch (_that) {
case _WizardCreatedSeason():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WizardCreatedSeason value)?  $default,){
final _that = this;
switch (_that) {
case _WizardCreatedSeason() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  int number,  String title)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WizardCreatedSeason() when $default != null:
return $default(_that.id,_that.number,_that.title);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  int number,  String title)  $default,) {final _that = this;
switch (_that) {
case _WizardCreatedSeason():
return $default(_that.id,_that.number,_that.title);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  int number,  String title)?  $default,) {final _that = this;
switch (_that) {
case _WizardCreatedSeason() when $default != null:
return $default(_that.id,_that.number,_that.title);case _:
  return null;

}
}

}

/// @nodoc


class _WizardCreatedSeason implements WizardCreatedSeason {
  const _WizardCreatedSeason({required this.id, required this.number, this.title = ''});
  

@override final  String id;
@override final  int number;
@override@JsonKey() final  String title;

/// Create a copy of WizardCreatedSeason
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WizardCreatedSeasonCopyWith<_WizardCreatedSeason> get copyWith => __$WizardCreatedSeasonCopyWithImpl<_WizardCreatedSeason>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WizardCreatedSeason&&(identical(other.id, id) || other.id == id)&&(identical(other.number, number) || other.number == number)&&(identical(other.title, title) || other.title == title));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,number,title);
}

@override
String toString() {
    return 'WizardCreatedSeason(id: $id, number: $number, title: $title)';
}


}

/// @nodoc
abstract mixin class _$WizardCreatedSeasonCopyWith<$Res> implements $WizardCreatedSeasonCopyWith<$Res> {
  factory _$WizardCreatedSeasonCopyWith(_WizardCreatedSeason value, $Res Function(_WizardCreatedSeason) _then) = __$WizardCreatedSeasonCopyWithImpl;
@override @useResult
$Res call({
 String id, int number, String title
});




}
/// @nodoc
class __$WizardCreatedSeasonCopyWithImpl<$Res>
    implements _$WizardCreatedSeasonCopyWith<$Res> {
  __$WizardCreatedSeasonCopyWithImpl(this._self, this._then);

  final _WizardCreatedSeason _self;
  final $Res Function(_WizardCreatedSeason) _then;

/// Create a copy of WizardCreatedSeason
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? number = null,Object? title = null,}) {
  return _then(_WizardCreatedSeason(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,number: null == number ? _self.number : number // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$WizardCreatedBlock {

 String get id; int get number; String get title; int get episodeCount; int get episodesCreated;
/// Create a copy of WizardCreatedBlock
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WizardCreatedBlockCopyWith<WizardCreatedBlock> get copyWith => _$WizardCreatedBlockCopyWithImpl<WizardCreatedBlock>(this as WizardCreatedBlock, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WizardCreatedBlock;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WizardCreatedBlock&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.number, _this.number) || other.number == _this.number)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.episodeCount, _this.episodeCount) || other.episodeCount == _this.episodeCount)&&(identical(other.episodesCreated, _this.episodesCreated) || other.episodesCreated == _this.episodesCreated));
}


@override
int get hashCode {
  final _this = this as WizardCreatedBlock;
  return Object.hash(runtimeType,_this.id,_this.number,_this.title,_this.episodeCount,_this.episodesCreated);
}

@override
String toString() {
  final _this = this as WizardCreatedBlock;
  return 'WizardCreatedBlock(id: ${_this.id}, number: ${_this.number}, title: ${_this.title}, episodeCount: ${_this.episodeCount}, episodesCreated: ${_this.episodesCreated})';
}


}

/// @nodoc
abstract mixin class $WizardCreatedBlockCopyWith<$Res>  {
  factory $WizardCreatedBlockCopyWith(WizardCreatedBlock value, $Res Function(WizardCreatedBlock) _then) = _$WizardCreatedBlockCopyWithImpl;
@useResult
$Res call({
 String id, int number, String title, int episodeCount, int episodesCreated
});




}
/// @nodoc
class _$WizardCreatedBlockCopyWithImpl<$Res>
    implements $WizardCreatedBlockCopyWith<$Res> {
  _$WizardCreatedBlockCopyWithImpl(this._self, this._then);

  final WizardCreatedBlock _self;
  final $Res Function(WizardCreatedBlock) _then;

/// Create a copy of WizardCreatedBlock
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? number = null,Object? title = null,Object? episodeCount = null,Object? episodesCreated = null,}) {
  return _then(WizardCreatedBlock(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,number: null == number ? _self.number : number // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,episodeCount: null == episodeCount ? _self.episodeCount : episodeCount // ignore: cast_nullable_to_non_nullable
as int,episodesCreated: null == episodesCreated ? _self.episodesCreated : episodesCreated // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [WizardCreatedBlock].
extension WizardCreatedBlockPatterns on WizardCreatedBlock {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WizardCreatedBlock value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WizardCreatedBlock() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WizardCreatedBlock value)  $default,){
final _that = this;
switch (_that) {
case _WizardCreatedBlock():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WizardCreatedBlock value)?  $default,){
final _that = this;
switch (_that) {
case _WizardCreatedBlock() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  int number,  String title,  int episodeCount,  int episodesCreated)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WizardCreatedBlock() when $default != null:
return $default(_that.id,_that.number,_that.title,_that.episodeCount,_that.episodesCreated);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  int number,  String title,  int episodeCount,  int episodesCreated)  $default,) {final _that = this;
switch (_that) {
case _WizardCreatedBlock():
return $default(_that.id,_that.number,_that.title,_that.episodeCount,_that.episodesCreated);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  int number,  String title,  int episodeCount,  int episodesCreated)?  $default,) {final _that = this;
switch (_that) {
case _WizardCreatedBlock() when $default != null:
return $default(_that.id,_that.number,_that.title,_that.episodeCount,_that.episodesCreated);case _:
  return null;

}
}

}

/// @nodoc


class _WizardCreatedBlock implements WizardCreatedBlock {
  const _WizardCreatedBlock({required this.id, required this.number, this.title = '', required this.episodeCount, this.episodesCreated = 0});
  

@override final  String id;
@override final  int number;
@override@JsonKey() final  String title;
@override final  int episodeCount;
@override@JsonKey() final  int episodesCreated;

/// Create a copy of WizardCreatedBlock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WizardCreatedBlockCopyWith<_WizardCreatedBlock> get copyWith => __$WizardCreatedBlockCopyWithImpl<_WizardCreatedBlock>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WizardCreatedBlock&&(identical(other.id, id) || other.id == id)&&(identical(other.number, number) || other.number == number)&&(identical(other.title, title) || other.title == title)&&(identical(other.episodeCount, episodeCount) || other.episodeCount == episodeCount)&&(identical(other.episodesCreated, episodesCreated) || other.episodesCreated == episodesCreated));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,number,title,episodeCount,episodesCreated);
}

@override
String toString() {
    return 'WizardCreatedBlock(id: $id, number: $number, title: $title, episodeCount: $episodeCount, episodesCreated: $episodesCreated)';
}


}

/// @nodoc
abstract mixin class _$WizardCreatedBlockCopyWith<$Res> implements $WizardCreatedBlockCopyWith<$Res> {
  factory _$WizardCreatedBlockCopyWith(_WizardCreatedBlock value, $Res Function(_WizardCreatedBlock) _then) = __$WizardCreatedBlockCopyWithImpl;
@override @useResult
$Res call({
 String id, int number, String title, int episodeCount, int episodesCreated
});




}
/// @nodoc
class __$WizardCreatedBlockCopyWithImpl<$Res>
    implements _$WizardCreatedBlockCopyWith<$Res> {
  __$WizardCreatedBlockCopyWithImpl(this._self, this._then);

  final _WizardCreatedBlock _self;
  final $Res Function(_WizardCreatedBlock) _then;

/// Create a copy of WizardCreatedBlock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? number = null,Object? title = null,Object? episodeCount = null,Object? episodesCreated = null,}) {
  return _then(_WizardCreatedBlock(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,number: null == number ? _self.number : number // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,episodeCount: null == episodeCount ? _self.episodeCount : episodeCount // ignore: cast_nullable_to_non_nullable
as int,episodesCreated: null == episodesCreated ? _self.episodesCreated : episodesCreated // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$SetupWizardState {

/// Current navigation step (Season → Blocks → Review).
 SetupWizardStep get step;/// Lifecycle phase.
 SetupWizardPhase get phase;/// Season number (smart default = highest existing + 1).
 int get seasonNumber;/// The first FREE series-scoped block number for this dispatch (derived
/// from the series' existing blocks at wizard open — the backend
/// enforces block-number uniqueness per SERIES,
/// `idx_projection_block_series_number`, not per season). Draft `i`
/// renders and dispatches as block `nextBlockNumber + i`; the number
/// is read-only information, never a field.
 int get nextBlockNumber;/// The first FREE series-scoped EPISODE number (`same backend pattern:
/// `idx_projection_episode_series_number`). The whole hierarchy is
/// numbered per series — the wizard assigns the drafts' episodes
/// sequentially across blocks starting here; read-only info.
 int get nextEpisodeNumber;/// Optional season name.
 String get seasonName;/// Block drafts (always ≥ 1 by default; removable).
 List<BlockDraft> get blocks;/// Created season (set during dispatch, kept for the summary).
 WizardCreatedSeason? get createdSeason;/// Created blocks with their episode progress (created-so-far).
 List<WizardCreatedBlock> get createdBlocks;/// Number of acknowledged commands in the current dispatch plan.
 int get dispatchDone;/// Total commands of the current dispatch plan.
 int get dispatchTotal;/// The in-flight sub-step label (e.g. the block/episode being created).
 String get dispatchLabel;/// Whether the current step's inputs validate (reported by the step
/// widget from the PURE validation functions on every user edit —
/// parse-invalid text never reaches the controller's fields, so this
/// is the "Weiter" gate). Reset on step navigation.
 bool get stepValid;/// The failed command's problem (partial-failure phase), keyed on the
/// stable `code` — the screen never renders backend `detail` text.
 ProblemError? get failure;
/// Create a copy of SetupWizardState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetupWizardStateCopyWith<SetupWizardState> get copyWith => _$SetupWizardStateCopyWithImpl<SetupWizardState>(this as SetupWizardState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SetupWizardState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SetupWizardState&&(identical(other.step, _this.step) || other.step == _this.step)&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.seasonNumber, _this.seasonNumber) || other.seasonNumber == _this.seasonNumber)&&(identical(other.nextBlockNumber, _this.nextBlockNumber) || other.nextBlockNumber == _this.nextBlockNumber)&&(identical(other.nextEpisodeNumber, _this.nextEpisodeNumber) || other.nextEpisodeNumber == _this.nextEpisodeNumber)&&(identical(other.seasonName, _this.seasonName) || other.seasonName == _this.seasonName)&&const DeepCollectionEquality().equals(other.blocks, _this.blocks)&&(identical(other.createdSeason, _this.createdSeason) || other.createdSeason == _this.createdSeason)&&const DeepCollectionEquality().equals(other.createdBlocks, _this.createdBlocks)&&(identical(other.dispatchDone, _this.dispatchDone) || other.dispatchDone == _this.dispatchDone)&&(identical(other.dispatchTotal, _this.dispatchTotal) || other.dispatchTotal == _this.dispatchTotal)&&(identical(other.dispatchLabel, _this.dispatchLabel) || other.dispatchLabel == _this.dispatchLabel)&&(identical(other.stepValid, _this.stepValid) || other.stepValid == _this.stepValid)&&(identical(other.failure, _this.failure) || other.failure == _this.failure));
}


@override
int get hashCode {
  final _this = this as SetupWizardState;
  return Object.hash(runtimeType,_this.step,_this.phase,_this.seasonNumber,_this.nextBlockNumber,_this.nextEpisodeNumber,_this.seasonName,const DeepCollectionEquality().hash(_this.blocks),_this.createdSeason,const DeepCollectionEquality().hash(_this.createdBlocks),_this.dispatchDone,_this.dispatchTotal,_this.dispatchLabel,_this.stepValid,_this.failure);
}

@override
String toString() {
  final _this = this as SetupWizardState;
  return 'SetupWizardState(step: ${_this.step}, phase: ${_this.phase}, seasonNumber: ${_this.seasonNumber}, nextBlockNumber: ${_this.nextBlockNumber}, nextEpisodeNumber: ${_this.nextEpisodeNumber}, seasonName: ${_this.seasonName}, blocks: ${_this.blocks}, createdSeason: ${_this.createdSeason}, createdBlocks: ${_this.createdBlocks}, dispatchDone: ${_this.dispatchDone}, dispatchTotal: ${_this.dispatchTotal}, dispatchLabel: ${_this.dispatchLabel}, stepValid: ${_this.stepValid}, failure: ${_this.failure})';
}


}

/// @nodoc
abstract mixin class $SetupWizardStateCopyWith<$Res>  {
  factory $SetupWizardStateCopyWith(SetupWizardState value, $Res Function(SetupWizardState) _then) = _$SetupWizardStateCopyWithImpl;
@useResult
$Res call({
 SetupWizardStep step, SetupWizardPhase phase, int seasonNumber, int nextBlockNumber, int nextEpisodeNumber, String seasonName, List<BlockDraft> blocks, WizardCreatedSeason? createdSeason, List<WizardCreatedBlock> createdBlocks, int dispatchDone, int dispatchTotal, String dispatchLabel, bool stepValid, ProblemError? failure
});


$WizardCreatedSeasonCopyWith<$Res>? get createdSeason;

}
/// @nodoc
class _$SetupWizardStateCopyWithImpl<$Res>
    implements $SetupWizardStateCopyWith<$Res> {
  _$SetupWizardStateCopyWithImpl(this._self, this._then);

  final SetupWizardState _self;
  final $Res Function(SetupWizardState) _then;

/// Create a copy of SetupWizardState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? step = null,Object? phase = null,Object? seasonNumber = null,Object? nextBlockNumber = null,Object? nextEpisodeNumber = null,Object? seasonName = null,Object? blocks = null,Object? createdSeason = freezed,Object? createdBlocks = null,Object? dispatchDone = null,Object? dispatchTotal = null,Object? dispatchLabel = null,Object? stepValid = null,Object? failure = freezed,}) {
  return _then(SetupWizardState(
step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as SetupWizardStep,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as SetupWizardPhase,seasonNumber: null == seasonNumber ? _self.seasonNumber : seasonNumber // ignore: cast_nullable_to_non_nullable
as int,nextBlockNumber: null == nextBlockNumber ? _self.nextBlockNumber : nextBlockNumber // ignore: cast_nullable_to_non_nullable
as int,nextEpisodeNumber: null == nextEpisodeNumber ? _self.nextEpisodeNumber : nextEpisodeNumber // ignore: cast_nullable_to_non_nullable
as int,seasonName: null == seasonName ? _self.seasonName : seasonName // ignore: cast_nullable_to_non_nullable
as String,blocks: null == blocks ? _self.blocks : blocks // ignore: cast_nullable_to_non_nullable
as List<BlockDraft>,createdSeason: freezed == createdSeason ? _self.createdSeason : createdSeason // ignore: cast_nullable_to_non_nullable
as WizardCreatedSeason?,createdBlocks: null == createdBlocks ? _self.createdBlocks : createdBlocks // ignore: cast_nullable_to_non_nullable
as List<WizardCreatedBlock>,dispatchDone: null == dispatchDone ? _self.dispatchDone : dispatchDone // ignore: cast_nullable_to_non_nullable
as int,dispatchTotal: null == dispatchTotal ? _self.dispatchTotal : dispatchTotal // ignore: cast_nullable_to_non_nullable
as int,dispatchLabel: null == dispatchLabel ? _self.dispatchLabel : dispatchLabel // ignore: cast_nullable_to_non_nullable
as String,stepValid: null == stepValid ? _self.stepValid : stepValid // ignore: cast_nullable_to_non_nullable
as bool,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as ProblemError?,
  ));
}
/// Create a copy of SetupWizardState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WizardCreatedSeasonCopyWith<$Res>? get createdSeason {
    if (_self.createdSeason == null) {
    return null;
  }

  return $WizardCreatedSeasonCopyWith<$Res>(_self.createdSeason!, (value) {
    return _then(_self.copyWith(createdSeason: value));
  });
}
}


/// Adds pattern-matching-related methods to [SetupWizardState].
extension SetupWizardStatePatterns on SetupWizardState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SetupWizardState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SetupWizardState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SetupWizardState value)  $default,){
final _that = this;
switch (_that) {
case _SetupWizardState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SetupWizardState value)?  $default,){
final _that = this;
switch (_that) {
case _SetupWizardState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SetupWizardStep step,  SetupWizardPhase phase,  int seasonNumber,  int nextBlockNumber,  int nextEpisodeNumber,  String seasonName,  List<BlockDraft> blocks,  WizardCreatedSeason? createdSeason,  List<WizardCreatedBlock> createdBlocks,  int dispatchDone,  int dispatchTotal,  String dispatchLabel,  bool stepValid,  ProblemError? failure)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SetupWizardState() when $default != null:
return $default(_that.step,_that.phase,_that.seasonNumber,_that.nextBlockNumber,_that.nextEpisodeNumber,_that.seasonName,_that.blocks,_that.createdSeason,_that.createdBlocks,_that.dispatchDone,_that.dispatchTotal,_that.dispatchLabel,_that.stepValid,_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SetupWizardStep step,  SetupWizardPhase phase,  int seasonNumber,  int nextBlockNumber,  int nextEpisodeNumber,  String seasonName,  List<BlockDraft> blocks,  WizardCreatedSeason? createdSeason,  List<WizardCreatedBlock> createdBlocks,  int dispatchDone,  int dispatchTotal,  String dispatchLabel,  bool stepValid,  ProblemError? failure)  $default,) {final _that = this;
switch (_that) {
case _SetupWizardState():
return $default(_that.step,_that.phase,_that.seasonNumber,_that.nextBlockNumber,_that.nextEpisodeNumber,_that.seasonName,_that.blocks,_that.createdSeason,_that.createdBlocks,_that.dispatchDone,_that.dispatchTotal,_that.dispatchLabel,_that.stepValid,_that.failure);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SetupWizardStep step,  SetupWizardPhase phase,  int seasonNumber,  int nextBlockNumber,  int nextEpisodeNumber,  String seasonName,  List<BlockDraft> blocks,  WizardCreatedSeason? createdSeason,  List<WizardCreatedBlock> createdBlocks,  int dispatchDone,  int dispatchTotal,  String dispatchLabel,  bool stepValid,  ProblemError? failure)?  $default,) {final _that = this;
switch (_that) {
case _SetupWizardState() when $default != null:
return $default(_that.step,_that.phase,_that.seasonNumber,_that.nextBlockNumber,_that.nextEpisodeNumber,_that.seasonName,_that.blocks,_that.createdSeason,_that.createdBlocks,_that.dispatchDone,_that.dispatchTotal,_that.dispatchLabel,_that.stepValid,_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class _SetupWizardState extends SetupWizardState {
  const _SetupWizardState({this.step = SetupWizardStep.season, this.phase = SetupWizardPhase.editing, this.seasonNumber = 1, this.nextBlockNumber = 1, this.nextEpisodeNumber = 1, this.seasonName = '',  List<BlockDraft> blocks = const <BlockDraft>[], this.createdSeason,  List<WizardCreatedBlock> createdBlocks = const <WizardCreatedBlock>[], this.dispatchDone = 0, this.dispatchTotal = 0, this.dispatchLabel = '', this.stepValid = true, this.failure}): _blocks = blocks,_createdBlocks = createdBlocks,super._();
  

/// Current navigation step (Season → Blocks → Review).
@override@JsonKey() final  SetupWizardStep step;
/// Lifecycle phase.
@override@JsonKey() final  SetupWizardPhase phase;
/// Season number (smart default = highest existing + 1).
@override@JsonKey() final  int seasonNumber;
/// The first FREE series-scoped block number for this dispatch (derived
/// from the series' existing blocks at wizard open — the backend
/// enforces block-number uniqueness per SERIES,
/// `idx_projection_block_series_number`, not per season). Draft `i`
/// renders and dispatches as block `nextBlockNumber + i`; the number
/// is read-only information, never a field.
@override@JsonKey() final  int nextBlockNumber;
/// The first FREE series-scoped EPISODE number (`same backend pattern:
/// `idx_projection_episode_series_number`). The whole hierarchy is
/// numbered per series — the wizard assigns the drafts' episodes
/// sequentially across blocks starting here; read-only info.
@override@JsonKey() final  int nextEpisodeNumber;
/// Optional season name.
@override@JsonKey() final  String seasonName;
/// Block drafts (always ≥ 1 by default; removable).
 final  List<BlockDraft> _blocks;
/// Block drafts (always ≥ 1 by default; removable).
@override@JsonKey() List<BlockDraft> get blocks {
  if (_blocks is EqualUnmodifiableListView) return _blocks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_blocks);
}

/// Created season (set during dispatch, kept for the summary).
@override final  WizardCreatedSeason? createdSeason;
/// Created blocks with their episode progress (created-so-far).
 final  List<WizardCreatedBlock> _createdBlocks;
/// Created blocks with their episode progress (created-so-far).
@override@JsonKey() List<WizardCreatedBlock> get createdBlocks {
  if (_createdBlocks is EqualUnmodifiableListView) return _createdBlocks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_createdBlocks);
}

/// Number of acknowledged commands in the current dispatch plan.
@override@JsonKey() final  int dispatchDone;
/// Total commands of the current dispatch plan.
@override@JsonKey() final  int dispatchTotal;
/// The in-flight sub-step label (e.g. the block/episode being created).
@override@JsonKey() final  String dispatchLabel;
/// Whether the current step's inputs validate (reported by the step
/// widget from the PURE validation functions on every user edit —
/// parse-invalid text never reaches the controller's fields, so this
/// is the "Weiter" gate). Reset on step navigation.
@override@JsonKey() final  bool stepValid;
/// The failed command's problem (partial-failure phase), keyed on the
/// stable `code` — the screen never renders backend `detail` text.
@override final  ProblemError? failure;

/// Create a copy of SetupWizardState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SetupWizardStateCopyWith<_SetupWizardState> get copyWith => __$SetupWizardStateCopyWithImpl<_SetupWizardState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SetupWizardState&&(identical(other.step, step) || other.step == step)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.seasonNumber, seasonNumber) || other.seasonNumber == seasonNumber)&&(identical(other.nextBlockNumber, nextBlockNumber) || other.nextBlockNumber == nextBlockNumber)&&(identical(other.nextEpisodeNumber, nextEpisodeNumber) || other.nextEpisodeNumber == nextEpisodeNumber)&&(identical(other.seasonName, seasonName) || other.seasonName == seasonName)&&const DeepCollectionEquality().equals(other.blocks, _blocks)&&(identical(other.createdSeason, createdSeason) || other.createdSeason == createdSeason)&&const DeepCollectionEquality().equals(other.createdBlocks, _createdBlocks)&&(identical(other.dispatchDone, dispatchDone) || other.dispatchDone == dispatchDone)&&(identical(other.dispatchTotal, dispatchTotal) || other.dispatchTotal == dispatchTotal)&&(identical(other.dispatchLabel, dispatchLabel) || other.dispatchLabel == dispatchLabel)&&(identical(other.stepValid, stepValid) || other.stepValid == stepValid)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,step,phase,seasonNumber,nextBlockNumber,nextEpisodeNumber,seasonName,const DeepCollectionEquality().hash(_blocks),createdSeason,const DeepCollectionEquality().hash(_createdBlocks),dispatchDone,dispatchTotal,dispatchLabel,stepValid,failure);
}

@override
String toString() {
    return 'SetupWizardState(step: $step, phase: $phase, seasonNumber: $seasonNumber, nextBlockNumber: $nextBlockNumber, nextEpisodeNumber: $nextEpisodeNumber, seasonName: $seasonName, blocks: $blocks, createdSeason: $createdSeason, createdBlocks: $createdBlocks, dispatchDone: $dispatchDone, dispatchTotal: $dispatchTotal, dispatchLabel: $dispatchLabel, stepValid: $stepValid, failure: $failure)';
}


}

/// @nodoc
abstract mixin class _$SetupWizardStateCopyWith<$Res> implements $SetupWizardStateCopyWith<$Res> {
  factory _$SetupWizardStateCopyWith(_SetupWizardState value, $Res Function(_SetupWizardState) _then) = __$SetupWizardStateCopyWithImpl;
@override @useResult
$Res call({
 SetupWizardStep step, SetupWizardPhase phase, int seasonNumber, int nextBlockNumber, int nextEpisodeNumber, String seasonName, List<BlockDraft> blocks, WizardCreatedSeason? createdSeason, List<WizardCreatedBlock> createdBlocks, int dispatchDone, int dispatchTotal, String dispatchLabel, bool stepValid, ProblemError? failure
});


@override $WizardCreatedSeasonCopyWith<$Res>? get createdSeason;

}
/// @nodoc
class __$SetupWizardStateCopyWithImpl<$Res>
    implements _$SetupWizardStateCopyWith<$Res> {
  __$SetupWizardStateCopyWithImpl(this._self, this._then);

  final _SetupWizardState _self;
  final $Res Function(_SetupWizardState) _then;

/// Create a copy of SetupWizardState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? step = null,Object? phase = null,Object? seasonNumber = null,Object? nextBlockNumber = null,Object? nextEpisodeNumber = null,Object? seasonName = null,Object? blocks = null,Object? createdSeason = freezed,Object? createdBlocks = null,Object? dispatchDone = null,Object? dispatchTotal = null,Object? dispatchLabel = null,Object? stepValid = null,Object? failure = freezed,}) {
  return _then(_SetupWizardState(
step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as SetupWizardStep,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as SetupWizardPhase,seasonNumber: null == seasonNumber ? _self.seasonNumber : seasonNumber // ignore: cast_nullable_to_non_nullable
as int,nextBlockNumber: null == nextBlockNumber ? _self.nextBlockNumber : nextBlockNumber // ignore: cast_nullable_to_non_nullable
as int,nextEpisodeNumber: null == nextEpisodeNumber ? _self.nextEpisodeNumber : nextEpisodeNumber // ignore: cast_nullable_to_non_nullable
as int,seasonName: null == seasonName ? _self.seasonName : seasonName // ignore: cast_nullable_to_non_nullable
as String,blocks: null == blocks ? _self._blocks : blocks // ignore: cast_nullable_to_non_nullable
as List<BlockDraft>,createdSeason: freezed == createdSeason ? _self.createdSeason : createdSeason // ignore: cast_nullable_to_non_nullable
as WizardCreatedSeason?,createdBlocks: null == createdBlocks ? _self._createdBlocks : createdBlocks // ignore: cast_nullable_to_non_nullable
as List<WizardCreatedBlock>,dispatchDone: null == dispatchDone ? _self.dispatchDone : dispatchDone // ignore: cast_nullable_to_non_nullable
as int,dispatchTotal: null == dispatchTotal ? _self.dispatchTotal : dispatchTotal // ignore: cast_nullable_to_non_nullable
as int,dispatchLabel: null == dispatchLabel ? _self.dispatchLabel : dispatchLabel // ignore: cast_nullable_to_non_nullable
as String,stepValid: null == stepValid ? _self.stepValid : stepValid // ignore: cast_nullable_to_non_nullable
as bool,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as ProblemError?,
  ));
}

/// Create a copy of SetupWizardState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WizardCreatedSeasonCopyWith<$Res>? get createdSeason {
    if (_self.createdSeason == null) {
    return null;
  }

  return $WizardCreatedSeasonCopyWith<$Res>(_self.createdSeason!, (value) {
    return _then(_self.copyWith(createdSeason: value));
  });
}
}

// dart format on
