// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_outfit_origin.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DraftOutfitOrigin extends DraftOutfitOrigin {
  @override
  final OneOf oneOf;

  factory _$DraftOutfitOrigin(
          [void Function(DraftOutfitOriginBuilder)? updates]) =>
      (DraftOutfitOriginBuilder()..update(updates))._build();

  _$DraftOutfitOrigin._({required this.oneOf}) : super._();
  @override
  DraftOutfitOrigin rebuild(void Function(DraftOutfitOriginBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DraftOutfitOriginBuilder toBuilder() =>
      DraftOutfitOriginBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DraftOutfitOrigin && oneOf == other.oneOf;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, oneOf.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DraftOutfitOrigin')
          ..add('oneOf', oneOf))
        .toString();
  }
}

class DraftOutfitOriginBuilder
    implements Builder<DraftOutfitOrigin, DraftOutfitOriginBuilder> {
  _$DraftOutfitOrigin? _$v;

  OneOf? _oneOf;
  OneOf? get oneOf => _$this._oneOf;
  set oneOf(OneOf? oneOf) => _$this._oneOf = oneOf;

  DraftOutfitOriginBuilder() {
    DraftOutfitOrigin._defaults(this);
  }

  DraftOutfitOriginBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _oneOf = $v.oneOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DraftOutfitOrigin other) {
    _$v = other as _$DraftOutfitOrigin;
  }

  @override
  void update(void Function(DraftOutfitOriginBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DraftOutfitOrigin build() => _build();

  _$DraftOutfitOrigin _build() {
    final _$result = _$v ??
        _$DraftOutfitOrigin._(
          oneOf: BuiltValueNullFieldError.checkNotNull(
              oneOf, r'DraftOutfitOrigin', 'oneOf'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
