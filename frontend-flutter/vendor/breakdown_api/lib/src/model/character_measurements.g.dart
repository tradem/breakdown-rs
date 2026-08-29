// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'character_measurements.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CharacterMeasurements extends CharacterMeasurements {
  @override
  final String chest;
  @override
  final String hatSize;
  @override
  final String height;
  @override
  final String hips;
  @override
  final String shoeSize;
  @override
  final String waist;
  @override
  final String weight;

  factory _$CharacterMeasurements(
          [void Function(CharacterMeasurementsBuilder)? updates]) =>
      (CharacterMeasurementsBuilder()..update(updates))._build();

  _$CharacterMeasurements._(
      {required this.chest,
      required this.hatSize,
      required this.height,
      required this.hips,
      required this.shoeSize,
      required this.waist,
      required this.weight})
      : super._();
  @override
  CharacterMeasurements rebuild(
          void Function(CharacterMeasurementsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CharacterMeasurementsBuilder toBuilder() =>
      CharacterMeasurementsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CharacterMeasurements &&
        chest == other.chest &&
        hatSize == other.hatSize &&
        height == other.height &&
        hips == other.hips &&
        shoeSize == other.shoeSize &&
        waist == other.waist &&
        weight == other.weight;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, chest.hashCode);
    _$hash = $jc(_$hash, hatSize.hashCode);
    _$hash = $jc(_$hash, height.hashCode);
    _$hash = $jc(_$hash, hips.hashCode);
    _$hash = $jc(_$hash, shoeSize.hashCode);
    _$hash = $jc(_$hash, waist.hashCode);
    _$hash = $jc(_$hash, weight.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CharacterMeasurements')
          ..add('chest', chest)
          ..add('hatSize', hatSize)
          ..add('height', height)
          ..add('hips', hips)
          ..add('shoeSize', shoeSize)
          ..add('waist', waist)
          ..add('weight', weight))
        .toString();
  }
}

class CharacterMeasurementsBuilder
    implements Builder<CharacterMeasurements, CharacterMeasurementsBuilder> {
  _$CharacterMeasurements? _$v;

  String? _chest;
  String? get chest => _$this._chest;
  set chest(String? chest) => _$this._chest = chest;

  String? _hatSize;
  String? get hatSize => _$this._hatSize;
  set hatSize(String? hatSize) => _$this._hatSize = hatSize;

  String? _height;
  String? get height => _$this._height;
  set height(String? height) => _$this._height = height;

  String? _hips;
  String? get hips => _$this._hips;
  set hips(String? hips) => _$this._hips = hips;

  String? _shoeSize;
  String? get shoeSize => _$this._shoeSize;
  set shoeSize(String? shoeSize) => _$this._shoeSize = shoeSize;

  String? _waist;
  String? get waist => _$this._waist;
  set waist(String? waist) => _$this._waist = waist;

  String? _weight;
  String? get weight => _$this._weight;
  set weight(String? weight) => _$this._weight = weight;

  CharacterMeasurementsBuilder() {
    CharacterMeasurements._defaults(this);
  }

  CharacterMeasurementsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _chest = $v.chest;
      _hatSize = $v.hatSize;
      _height = $v.height;
      _hips = $v.hips;
      _shoeSize = $v.shoeSize;
      _waist = $v.waist;
      _weight = $v.weight;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CharacterMeasurements other) {
    _$v = other as _$CharacterMeasurements;
  }

  @override
  void update(void Function(CharacterMeasurementsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CharacterMeasurements build() => _build();

  _$CharacterMeasurements _build() {
    final _$result = _$v ??
        _$CharacterMeasurements._(
          chest: BuiltValueNullFieldError.checkNotNull(
              chest, r'CharacterMeasurements', 'chest'),
          hatSize: BuiltValueNullFieldError.checkNotNull(
              hatSize, r'CharacterMeasurements', 'hatSize'),
          height: BuiltValueNullFieldError.checkNotNull(
              height, r'CharacterMeasurements', 'height'),
          hips: BuiltValueNullFieldError.checkNotNull(
              hips, r'CharacterMeasurements', 'hips'),
          shoeSize: BuiltValueNullFieldError.checkNotNull(
              shoeSize, r'CharacterMeasurements', 'shoeSize'),
          waist: BuiltValueNullFieldError.checkNotNull(
              waist, r'CharacterMeasurements', 'waist'),
          weight: BuiltValueNullFieldError.checkNotNull(
              weight, r'CharacterMeasurements', 'weight'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
