// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_binding_one_of2.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhotoBindingOneOf2 extends PhotoBindingOneOf2 {
  @override
  final PhotoBindingOneOf2Continuity continuity;

  factory _$PhotoBindingOneOf2(
          [void Function(PhotoBindingOneOf2Builder)? updates]) =>
      (PhotoBindingOneOf2Builder()..update(updates))._build();

  _$PhotoBindingOneOf2._({required this.continuity}) : super._();
  @override
  PhotoBindingOneOf2 rebuild(
          void Function(PhotoBindingOneOf2Builder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhotoBindingOneOf2Builder toBuilder() =>
      PhotoBindingOneOf2Builder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhotoBindingOneOf2 && continuity == other.continuity;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, continuity.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhotoBindingOneOf2')
          ..add('continuity', continuity))
        .toString();
  }
}

class PhotoBindingOneOf2Builder
    implements Builder<PhotoBindingOneOf2, PhotoBindingOneOf2Builder> {
  _$PhotoBindingOneOf2? _$v;

  PhotoBindingOneOf2ContinuityBuilder? _continuity;
  PhotoBindingOneOf2ContinuityBuilder get continuity =>
      _$this._continuity ??= PhotoBindingOneOf2ContinuityBuilder();
  set continuity(PhotoBindingOneOf2ContinuityBuilder? continuity) =>
      _$this._continuity = continuity;

  PhotoBindingOneOf2Builder() {
    PhotoBindingOneOf2._defaults(this);
  }

  PhotoBindingOneOf2Builder get _$this {
    final $v = _$v;
    if ($v != null) {
      _continuity = $v.continuity.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhotoBindingOneOf2 other) {
    _$v = other as _$PhotoBindingOneOf2;
  }

  @override
  void update(void Function(PhotoBindingOneOf2Builder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhotoBindingOneOf2 build() => _build();

  _$PhotoBindingOneOf2 _build() {
    _$PhotoBindingOneOf2 _$result;
    try {
      _$result = _$v ??
          _$PhotoBindingOneOf2._(
            continuity: continuity.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'continuity';
        continuity.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'PhotoBindingOneOf2', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
