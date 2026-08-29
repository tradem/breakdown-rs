// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ModelInfo extends ModelInfo {
  @override
  final String? displayName;
  @override
  final String id;
  @override
  final LlmProvider provider;

  factory _$ModelInfo([void Function(ModelInfoBuilder)? updates]) =>
      (ModelInfoBuilder()..update(updates))._build();

  _$ModelInfo._({this.displayName, required this.id, required this.provider})
      : super._();
  @override
  ModelInfo rebuild(void Function(ModelInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ModelInfoBuilder toBuilder() => ModelInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ModelInfo &&
        displayName == other.displayName &&
        id == other.id &&
        provider == other.provider;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModelInfo')
          ..add('displayName', displayName)
          ..add('id', id)
          ..add('provider', provider))
        .toString();
  }
}

class ModelInfoBuilder implements Builder<ModelInfo, ModelInfoBuilder> {
  _$ModelInfo? _$v;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  LlmProvider? _provider;
  LlmProvider? get provider => _$this._provider;
  set provider(LlmProvider? provider) => _$this._provider = provider;

  ModelInfoBuilder() {
    ModelInfo._defaults(this);
  }

  ModelInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _displayName = $v.displayName;
      _id = $v.id;
      _provider = $v.provider;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ModelInfo other) {
    _$v = other as _$ModelInfo;
  }

  @override
  void update(void Function(ModelInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ModelInfo build() => _build();

  _$ModelInfo _build() {
    final _$result = _$v ??
        _$ModelInfo._(
          displayName: displayName,
          id: BuiltValueNullFieldError.checkNotNull(id, r'ModelInfo', 'id'),
          provider: BuiltValueNullFieldError.checkNotNull(
              provider, r'ModelInfo', 'provider'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
