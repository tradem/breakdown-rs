// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_provider_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiProviderInfo extends AiProviderInfo {
  @override
  final String key;
  @override
  final LlmProvider provider;

  factory _$AiProviderInfo([void Function(AiProviderInfoBuilder)? updates]) =>
      (AiProviderInfoBuilder()..update(updates))._build();

  _$AiProviderInfo._({required this.key, required this.provider}) : super._();
  @override
  AiProviderInfo rebuild(void Function(AiProviderInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiProviderInfoBuilder toBuilder() => AiProviderInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiProviderInfo &&
        key == other.key &&
        provider == other.provider;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, key.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiProviderInfo')
          ..add('key', key)
          ..add('provider', provider))
        .toString();
  }
}

class AiProviderInfoBuilder
    implements Builder<AiProviderInfo, AiProviderInfoBuilder> {
  _$AiProviderInfo? _$v;

  String? _key;
  String? get key => _$this._key;
  set key(String? key) => _$this._key = key;

  LlmProvider? _provider;
  LlmProvider? get provider => _$this._provider;
  set provider(LlmProvider? provider) => _$this._provider = provider;

  AiProviderInfoBuilder() {
    AiProviderInfo._defaults(this);
  }

  AiProviderInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _key = $v.key;
      _provider = $v.provider;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiProviderInfo other) {
    _$v = other as _$AiProviderInfo;
  }

  @override
  void update(void Function(AiProviderInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiProviderInfo build() => _build();

  _$AiProviderInfo _build() {
    final _$result = _$v ??
        _$AiProviderInfo._(
          key: BuiltValueNullFieldError.checkNotNull(
              key, r'AiProviderInfo', 'key'),
          provider: BuiltValueNullFieldError.checkNotNull(
              provider, r'AiProviderInfo', 'provider'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
