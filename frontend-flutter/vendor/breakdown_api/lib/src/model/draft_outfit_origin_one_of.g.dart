// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_outfit_origin_one_of.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DraftOutfitOriginOneOf extends DraftOutfitOriginOneOf {
  @override
  final DraftOutfitOriginOneOfContinuedFromScene continuedFromScene;

  factory _$DraftOutfitOriginOneOf(
          [void Function(DraftOutfitOriginOneOfBuilder)? updates]) =>
      (DraftOutfitOriginOneOfBuilder()..update(updates))._build();

  _$DraftOutfitOriginOneOf._({required this.continuedFromScene}) : super._();
  @override
  DraftOutfitOriginOneOf rebuild(
          void Function(DraftOutfitOriginOneOfBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DraftOutfitOriginOneOfBuilder toBuilder() =>
      DraftOutfitOriginOneOfBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DraftOutfitOriginOneOf &&
        continuedFromScene == other.continuedFromScene;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, continuedFromScene.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DraftOutfitOriginOneOf')
          ..add('continuedFromScene', continuedFromScene))
        .toString();
  }
}

class DraftOutfitOriginOneOfBuilder
    implements Builder<DraftOutfitOriginOneOf, DraftOutfitOriginOneOfBuilder> {
  _$DraftOutfitOriginOneOf? _$v;

  DraftOutfitOriginOneOfContinuedFromSceneBuilder? _continuedFromScene;
  DraftOutfitOriginOneOfContinuedFromSceneBuilder get continuedFromScene =>
      _$this._continuedFromScene ??=
          DraftOutfitOriginOneOfContinuedFromSceneBuilder();
  set continuedFromScene(
          DraftOutfitOriginOneOfContinuedFromSceneBuilder?
              continuedFromScene) =>
      _$this._continuedFromScene = continuedFromScene;

  DraftOutfitOriginOneOfBuilder() {
    DraftOutfitOriginOneOf._defaults(this);
  }

  DraftOutfitOriginOneOfBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _continuedFromScene = $v.continuedFromScene.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DraftOutfitOriginOneOf other) {
    _$v = other as _$DraftOutfitOriginOneOf;
  }

  @override
  void update(void Function(DraftOutfitOriginOneOfBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DraftOutfitOriginOneOf build() => _build();

  _$DraftOutfitOriginOneOf _build() {
    _$DraftOutfitOriginOneOf _$result;
    try {
      _$result = _$v ??
          _$DraftOutfitOriginOneOf._(
            continuedFromScene: continuedFromScene.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'continuedFromScene';
        continuedFromScene.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'DraftOutfitOriginOneOf', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
