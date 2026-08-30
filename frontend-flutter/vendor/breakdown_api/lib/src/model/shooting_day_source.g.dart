// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shooting_day_source.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ShootingDaySource extends ShootingDaySource {
  @override
  final OneOf oneOf;

  factory _$ShootingDaySource(
          [void Function(ShootingDaySourceBuilder)? updates]) =>
      (ShootingDaySourceBuilder()..update(updates))._build();

  _$ShootingDaySource._({required this.oneOf}) : super._();
  @override
  ShootingDaySource rebuild(void Function(ShootingDaySourceBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ShootingDaySourceBuilder toBuilder() =>
      ShootingDaySourceBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ShootingDaySource && oneOf == other.oneOf;
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
    return (newBuiltValueToStringHelper(r'ShootingDaySource')
          ..add('oneOf', oneOf))
        .toString();
  }
}

class ShootingDaySourceBuilder
    implements Builder<ShootingDaySource, ShootingDaySourceBuilder> {
  _$ShootingDaySource? _$v;

  OneOf? _oneOf;
  OneOf? get oneOf => _$this._oneOf;
  set oneOf(OneOf? oneOf) => _$this._oneOf = oneOf;

  ShootingDaySourceBuilder() {
    ShootingDaySource._defaults(this);
  }

  ShootingDaySourceBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _oneOf = $v.oneOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ShootingDaySource other) {
    _$v = other as _$ShootingDaySource;
  }

  @override
  void update(void Function(ShootingDaySourceBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ShootingDaySource build() => _build();

  _$ShootingDaySource _build() {
    final _$result = _$v ??
        _$ShootingDaySource._(
          oneOf: BuiltValueNullFieldError.checkNotNull(
              oneOf, r'ShootingDaySource', 'oneOf'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
