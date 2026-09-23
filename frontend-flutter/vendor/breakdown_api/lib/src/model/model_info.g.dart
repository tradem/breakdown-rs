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
  @override
  final bool recommended;

  factory _$ModelInfo([void Function(ModelInfoBuilder)? updates]) =>
      (ModelInfoBuilder()..update(updates))._build();

  _$ModelInfo._(
      {this.displayName,
      required this.id,
      required this.provider,
      required this.recommended})
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
        provider == other.provider &&
        recommended == other.recommended;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, recommended.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ModelInfo')
          ..add('displayName', displayName)
          ..add('id', id)
          ..add('provider', provider)
          ..add('recommended', recommended))
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

  bool? _recommended;
  bool? get recommended => _$this._recommended;
  set recommended(bool? recommended) => _$this._recommended = recommended;

  ModelInfoBuilder() {
    ModelInfo._defaults(this);
  }

  ModelInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _displayName = $v.displayName;
      _id = $v.id;
      _provider = $v.provider;
      _recommended = $v.recommended;
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
          recommended: BuiltValueNullFieldError.checkNotNull(
              recommended, r'ModelInfo', 'recommended'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
