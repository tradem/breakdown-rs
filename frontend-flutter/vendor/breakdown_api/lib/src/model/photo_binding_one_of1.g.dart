// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_binding_one_of1.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhotoBindingOneOf1 extends PhotoBindingOneOf1 {
  @override
  final PhotoBindingOneOf1Outfit outfit;

  factory _$PhotoBindingOneOf1(
          [void Function(PhotoBindingOneOf1Builder)? updates]) =>
      (PhotoBindingOneOf1Builder()..update(updates))._build();

  _$PhotoBindingOneOf1._({required this.outfit}) : super._();
  @override
  PhotoBindingOneOf1 rebuild(
          void Function(PhotoBindingOneOf1Builder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhotoBindingOneOf1Builder toBuilder() =>
      PhotoBindingOneOf1Builder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhotoBindingOneOf1 && outfit == other.outfit;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, outfit.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhotoBindingOneOf1')
          ..add('outfit', outfit))
        .toString();
  }
}

class PhotoBindingOneOf1Builder
    implements Builder<PhotoBindingOneOf1, PhotoBindingOneOf1Builder> {
  _$PhotoBindingOneOf1? _$v;

  PhotoBindingOneOf1OutfitBuilder? _outfit;
  PhotoBindingOneOf1OutfitBuilder get outfit =>
      _$this._outfit ??= PhotoBindingOneOf1OutfitBuilder();
  set outfit(PhotoBindingOneOf1OutfitBuilder? outfit) =>
      _$this._outfit = outfit;

  PhotoBindingOneOf1Builder() {
    PhotoBindingOneOf1._defaults(this);
  }

  PhotoBindingOneOf1Builder get _$this {
    final $v = _$v;
    if ($v != null) {
      _outfit = $v.outfit.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhotoBindingOneOf1 other) {
    _$v = other as _$PhotoBindingOneOf1;
  }

  @override
  void update(void Function(PhotoBindingOneOf1Builder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhotoBindingOneOf1 build() => _build();

  _$PhotoBindingOneOf1 _build() {
    _$PhotoBindingOneOf1 _$result;
    try {
      _$result = _$v ??
          _$PhotoBindingOneOf1._(
            outfit: outfit.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'outfit';
        outfit.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'PhotoBindingOneOf1', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
