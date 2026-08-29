// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_ai_config_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateAiConfigRequest extends UpdateAiConfigRequest {
  @override
  final String assistantModel;
  @override
  final String? imageModel;
  @override
  final BuiltMap<String, String> prompts;
  @override
  final LlmProvider provider;
  @override
  final String vaultKeyId;
  @override
  final int version;

  factory _$UpdateAiConfigRequest(
          [void Function(UpdateAiConfigRequestBuilder)? updates]) =>
      (UpdateAiConfigRequestBuilder()..update(updates))._build();

  _$UpdateAiConfigRequest._(
      {required this.assistantModel,
      this.imageModel,
      required this.prompts,
      required this.provider,
      required this.vaultKeyId,
      required this.version})
      : super._();
  @override
  UpdateAiConfigRequest rebuild(
          void Function(UpdateAiConfigRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateAiConfigRequestBuilder toBuilder() =>
      UpdateAiConfigRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateAiConfigRequest &&
        assistantModel == other.assistantModel &&
        imageModel == other.imageModel &&
        prompts == other.prompts &&
        provider == other.provider &&
        vaultKeyId == other.vaultKeyId &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, assistantModel.hashCode);
    _$hash = $jc(_$hash, imageModel.hashCode);
    _$hash = $jc(_$hash, prompts.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, vaultKeyId.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateAiConfigRequest')
          ..add('assistantModel', assistantModel)
          ..add('imageModel', imageModel)
          ..add('prompts', prompts)
          ..add('provider', provider)
          ..add('vaultKeyId', vaultKeyId)
          ..add('version', version))
        .toString();
  }
}

class UpdateAiConfigRequestBuilder
    implements Builder<UpdateAiConfigRequest, UpdateAiConfigRequestBuilder> {
  _$UpdateAiConfigRequest? _$v;

  String? _assistantModel;
  String? get assistantModel => _$this._assistantModel;
  set assistantModel(String? assistantModel) =>
      _$this._assistantModel = assistantModel;

  String? _imageModel;
  String? get imageModel => _$this._imageModel;
  set imageModel(String? imageModel) => _$this._imageModel = imageModel;

  MapBuilder<String, String>? _prompts;
  MapBuilder<String, String> get prompts =>
      _$this._prompts ??= MapBuilder<String, String>();
  set prompts(MapBuilder<String, String>? prompts) => _$this._prompts = prompts;

  LlmProvider? _provider;
  LlmProvider? get provider => _$this._provider;
  set provider(LlmProvider? provider) => _$this._provider = provider;

  String? _vaultKeyId;
  String? get vaultKeyId => _$this._vaultKeyId;
  set vaultKeyId(String? vaultKeyId) => _$this._vaultKeyId = vaultKeyId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdateAiConfigRequestBuilder() {
    UpdateAiConfigRequest._defaults(this);
  }

  UpdateAiConfigRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _assistantModel = $v.assistantModel;
      _imageModel = $v.imageModel;
      _prompts = $v.prompts.toBuilder();
      _provider = $v.provider;
      _vaultKeyId = $v.vaultKeyId;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateAiConfigRequest other) {
    _$v = other as _$UpdateAiConfigRequest;
  }

  @override
  void update(void Function(UpdateAiConfigRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateAiConfigRequest build() => _build();

  _$UpdateAiConfigRequest _build() {
    _$UpdateAiConfigRequest _$result;
    try {
      _$result = _$v ??
          _$UpdateAiConfigRequest._(
            assistantModel: BuiltValueNullFieldError.checkNotNull(
                assistantModel, r'UpdateAiConfigRequest', 'assistantModel'),
            imageModel: imageModel,
            prompts: prompts.build(),
            provider: BuiltValueNullFieldError.checkNotNull(
                provider, r'UpdateAiConfigRequest', 'provider'),
            vaultKeyId: BuiltValueNullFieldError.checkNotNull(
                vaultKeyId, r'UpdateAiConfigRequest', 'vaultKeyId'),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'UpdateAiConfigRequest', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'prompts';
        prompts.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'UpdateAiConfigRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
