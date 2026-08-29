// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_binding.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhotoBinding extends PhotoBinding {
  @override
  final OneOf oneOf;

  factory _$PhotoBinding([void Function(PhotoBindingBuilder)? updates]) =>
      (PhotoBindingBuilder()..update(updates))._build();

  _$PhotoBinding._({required this.oneOf}) : super._();
  @override
  PhotoBinding rebuild(void Function(PhotoBindingBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhotoBindingBuilder toBuilder() => PhotoBindingBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhotoBinding && oneOf == other.oneOf;
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
    return (newBuiltValueToStringHelper(r'PhotoBinding')..add('oneOf', oneOf))
        .toString();
  }
}

class PhotoBindingBuilder
    implements Builder<PhotoBinding, PhotoBindingBuilder> {
  _$PhotoBinding? _$v;

  OneOf? _oneOf;
  OneOf? get oneOf => _$this._oneOf;
  set oneOf(OneOf? oneOf) => _$this._oneOf = oneOf;

  PhotoBindingBuilder() {
    PhotoBinding._defaults(this);
  }

  PhotoBindingBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _oneOf = $v.oneOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhotoBinding other) {
    _$v = other as _$PhotoBinding;
  }

  @override
  void update(void Function(PhotoBindingBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhotoBinding build() => _build();

  _$PhotoBinding _build() {
    final _$result = _$v ??
        _$PhotoBinding._(
          oneOf: BuiltValueNullFieldError.checkNotNull(
              oneOf, r'PhotoBinding', 'oneOf'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
