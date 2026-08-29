// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_bytes_query.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhotoBytesQuery extends PhotoBytesQuery {
  @override
  final String? variant;

  factory _$PhotoBytesQuery([void Function(PhotoBytesQueryBuilder)? updates]) =>
      (PhotoBytesQueryBuilder()..update(updates))._build();

  _$PhotoBytesQuery._({this.variant}) : super._();
  @override
  PhotoBytesQuery rebuild(void Function(PhotoBytesQueryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhotoBytesQueryBuilder toBuilder() => PhotoBytesQueryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhotoBytesQuery && variant == other.variant;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, variant.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhotoBytesQuery')
          ..add('variant', variant))
        .toString();
  }
}

class PhotoBytesQueryBuilder
    implements Builder<PhotoBytesQuery, PhotoBytesQueryBuilder> {
  _$PhotoBytesQuery? _$v;

  String? _variant;
  String? get variant => _$this._variant;
  set variant(String? variant) => _$this._variant = variant;

  PhotoBytesQueryBuilder() {
    PhotoBytesQuery._defaults(this);
  }

  PhotoBytesQueryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _variant = $v.variant;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhotoBytesQuery other) {
    _$v = other as _$PhotoBytesQuery;
  }

  @override
  void update(void Function(PhotoBytesQueryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhotoBytesQuery build() => _build();

  _$PhotoBytesQuery _build() {
    final _$result = _$v ??
        _$PhotoBytesQuery._(
          variant: variant,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
