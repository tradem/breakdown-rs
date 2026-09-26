// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_source.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SceneSource extends SceneSource {
  @override
  final OneOf oneOf;

  factory _$SceneSource([void Function(SceneSourceBuilder)? updates]) =>
      (SceneSourceBuilder()..update(updates))._build();

  _$SceneSource._({required this.oneOf}) : super._();
  @override
  SceneSource rebuild(void Function(SceneSourceBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SceneSourceBuilder toBuilder() => SceneSourceBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SceneSource && oneOf == other.oneOf;
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
    return (newBuiltValueToStringHelper(r'SceneSource')..add('oneOf', oneOf))
        .toString();
  }
}

class SceneSourceBuilder implements Builder<SceneSource, SceneSourceBuilder> {
  _$SceneSource? _$v;

  OneOf? _oneOf;
  OneOf? get oneOf => _$this._oneOf;
  set oneOf(OneOf? oneOf) => _$this._oneOf = oneOf;

  SceneSourceBuilder() {
    SceneSource._defaults(this);
  }

  SceneSourceBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _oneOf = $v.oneOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SceneSource other) {
    _$v = other as _$SceneSource;
  }

  @override
  void update(void Function(SceneSourceBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SceneSource build() => _build();

  _$SceneSource _build() {
    final _$result = _$v ??
        _$SceneSource._(
          oneOf: BuiltValueNullFieldError.checkNotNull(
              oneOf, r'SceneSource', 'oneOf'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
