// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meta_versions_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MetaVersionsResponse extends MetaVersionsResponse {
  @override
  final String api;
  @override
  final String core;
  @override
  final String infra;

  factory _$MetaVersionsResponse(
          [void Function(MetaVersionsResponseBuilder)? updates]) =>
      (MetaVersionsResponseBuilder()..update(updates))._build();

  _$MetaVersionsResponse._(
      {required this.api, required this.core, required this.infra})
      : super._();
  @override
  MetaVersionsResponse rebuild(
          void Function(MetaVersionsResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MetaVersionsResponseBuilder toBuilder() =>
      MetaVersionsResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MetaVersionsResponse &&
        api == other.api &&
        core == other.core &&
        infra == other.infra;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, api.hashCode);
    _$hash = $jc(_$hash, core.hashCode);
    _$hash = $jc(_$hash, infra.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MetaVersionsResponse')
          ..add('api', api)
          ..add('core', core)
          ..add('infra', infra))
        .toString();
  }
}

class MetaVersionsResponseBuilder
    implements Builder<MetaVersionsResponse, MetaVersionsResponseBuilder> {
  _$MetaVersionsResponse? _$v;

  String? _api;
  String? get api => _$this._api;
  set api(String? api) => _$this._api = api;

  String? _core;
  String? get core => _$this._core;
  set core(String? core) => _$this._core = core;

  String? _infra;
  String? get infra => _$this._infra;
  set infra(String? infra) => _$this._infra = infra;

  MetaVersionsResponseBuilder() {
    MetaVersionsResponse._defaults(this);
  }

  MetaVersionsResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _api = $v.api;
      _core = $v.core;
      _infra = $v.infra;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MetaVersionsResponse other) {
    _$v = other as _$MetaVersionsResponse;
  }

  @override
  void update(void Function(MetaVersionsResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MetaVersionsResponse build() => _build();

  _$MetaVersionsResponse _build() {
    final _$result = _$v ??
        _$MetaVersionsResponse._(
          api: BuiltValueNullFieldError.checkNotNull(
              api, r'MetaVersionsResponse', 'api'),
          core: BuiltValueNullFieldError.checkNotNull(
              core, r'MetaVersionsResponse', 'core'),
          infra: BuiltValueNullFieldError.checkNotNull(
              infra, r'MetaVersionsResponse', 'infra'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
