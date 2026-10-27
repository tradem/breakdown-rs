// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_binding_one_of1_outfit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhotoBindingOneOf1Outfit extends PhotoBindingOneOf1Outfit {
  @override
  final String outfitId;

  factory _$PhotoBindingOneOf1Outfit(
          [void Function(PhotoBindingOneOf1OutfitBuilder)? updates]) =>
      (PhotoBindingOneOf1OutfitBuilder()..update(updates))._build();

  _$PhotoBindingOneOf1Outfit._({required this.outfitId}) : super._();
  @override
  PhotoBindingOneOf1Outfit rebuild(
          void Function(PhotoBindingOneOf1OutfitBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhotoBindingOneOf1OutfitBuilder toBuilder() =>
      PhotoBindingOneOf1OutfitBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhotoBindingOneOf1Outfit && outfitId == other.outfitId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, outfitId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhotoBindingOneOf1Outfit')
          ..add('outfitId', outfitId))
        .toString();
  }
}

class PhotoBindingOneOf1OutfitBuilder
    implements
        Builder<PhotoBindingOneOf1Outfit, PhotoBindingOneOf1OutfitBuilder> {
  _$PhotoBindingOneOf1Outfit? _$v;

  String? _outfitId;
  String? get outfitId => _$this._outfitId;
  set outfitId(String? outfitId) => _$this._outfitId = outfitId;

  PhotoBindingOneOf1OutfitBuilder() {
    PhotoBindingOneOf1Outfit._defaults(this);
  }

  PhotoBindingOneOf1OutfitBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _outfitId = $v.outfitId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhotoBindingOneOf1Outfit other) {
    _$v = other as _$PhotoBindingOneOf1Outfit;
  }

  @override
  void update(void Function(PhotoBindingOneOf1OutfitBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhotoBindingOneOf1Outfit build() => _build();

  _$PhotoBindingOneOf1Outfit _build() {
    final _$result = _$v ??
        _$PhotoBindingOneOf1Outfit._(
          outfitId: BuiltValueNullFieldError.checkNotNull(
              outfitId, r'PhotoBindingOneOf1Outfit', 'outfitId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
