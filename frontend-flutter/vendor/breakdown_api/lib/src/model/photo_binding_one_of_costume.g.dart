// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_binding_one_of_costume.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhotoBindingOneOfCostume extends PhotoBindingOneOfCostume {
  @override
  final String costumeId;

  factory _$PhotoBindingOneOfCostume(
          [void Function(PhotoBindingOneOfCostumeBuilder)? updates]) =>
      (PhotoBindingOneOfCostumeBuilder()..update(updates))._build();

  _$PhotoBindingOneOfCostume._({required this.costumeId}) : super._();
  @override
  PhotoBindingOneOfCostume rebuild(
          void Function(PhotoBindingOneOfCostumeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhotoBindingOneOfCostumeBuilder toBuilder() =>
      PhotoBindingOneOfCostumeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhotoBindingOneOfCostume && costumeId == other.costumeId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, costumeId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhotoBindingOneOfCostume')
          ..add('costumeId', costumeId))
        .toString();
  }
}

class PhotoBindingOneOfCostumeBuilder
    implements
        Builder<PhotoBindingOneOfCostume, PhotoBindingOneOfCostumeBuilder> {
  _$PhotoBindingOneOfCostume? _$v;

  String? _costumeId;
  String? get costumeId => _$this._costumeId;
  set costumeId(String? costumeId) => _$this._costumeId = costumeId;

  PhotoBindingOneOfCostumeBuilder() {
    PhotoBindingOneOfCostume._defaults(this);
  }

  PhotoBindingOneOfCostumeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _costumeId = $v.costumeId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhotoBindingOneOfCostume other) {
    _$v = other as _$PhotoBindingOneOfCostume;
  }

  @override
  void update(void Function(PhotoBindingOneOfCostumeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhotoBindingOneOfCostume build() => _build();

  _$PhotoBindingOneOfCostume _build() {
    final _$result = _$v ??
        _$PhotoBindingOneOfCostume._(
          costumeId: BuiltValueNullFieldError.checkNotNull(
              costumeId, r'PhotoBindingOneOfCostume', 'costumeId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
