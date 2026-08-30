// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_ai_config_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateAiConfigRequest extends CreateAiConfigRequest {
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

  factory _$CreateAiConfigRequest(
          [void Function(CreateAiConfigRequestBuilder)? updates]) =>
      (CreateAiConfigRequestBuilder()..update(updates))._build();

  _$CreateAiConfigRequest._(
      {required this.assistantModel,
      this.imageModel,
      required this.prompts,
      required this.provider,
      required this.vaultKeyId})
      : super._();
  @override
  CreateAiConfigRequest rebuild(
          void Function(CreateAiConfigRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateAiConfigRequestBuilder toBuilder() =>
      CreateAiConfigRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateAiConfigRequest &&
        assistantModel == other.assistantModel &&
        imageModel == other.imageModel &&
        prompts == other.prompts &&
        provider == other.provider &&
        vaultKeyId == other.vaultKeyId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, assistantModel.hashCode);
    _$hash = $jc(_$hash, imageModel.hashCode);
    _$hash = $jc(_$hash, prompts.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, vaultKeyId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateAiConfigRequest')
          ..add('assistantModel', assistantModel)
          ..add('imageModel', imageModel)
          ..add('prompts', prompts)
          ..add('provider', provider)
          ..add('vaultKeyId', vaultKeyId))
        .toString();
  }
}

class CreateAiConfigRequestBuilder
    implements Builder<CreateAiConfigRequest, CreateAiConfigRequestBuilder> {
  _$CreateAiConfigRequest? _$v;

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

  CreateAiConfigRequestBuilder() {
    CreateAiConfigRequest._defaults(this);
  }

  CreateAiConfigRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _assistantModel = $v.assistantModel;
      _imageModel = $v.imageModel;
      _prompts = $v.prompts.toBuilder();
      _provider = $v.provider;
      _vaultKeyId = $v.vaultKeyId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateAiConfigRequest other) {
    _$v = other as _$CreateAiConfigRequest;
  }

  @override
  void update(void Function(CreateAiConfigRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateAiConfigRequest build() => _build();

  _$CreateAiConfigRequest _build() {
    _$CreateAiConfigRequest _$result;
    try {
      _$result = _$v ??
          _$CreateAiConfigRequest._(
            assistantModel: BuiltValueNullFieldError.checkNotNull(
                assistantModel, r'CreateAiConfigRequest', 'assistantModel'),
            imageModel: imageModel,
            prompts: prompts.build(),
            provider: BuiltValueNullFieldError.checkNotNull(
                provider, r'CreateAiConfigRequest', 'provider'),
            vaultKeyId: BuiltValueNullFieldError.checkNotNull(
                vaultKeyId, r'CreateAiConfigRequest', 'vaultKeyId'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'prompts';
        prompts.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'CreateAiConfigRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
