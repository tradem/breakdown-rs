// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_config_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiConfigView extends AiConfigView {
  @override
  final String assistantModel;
  @override
  final CostDisplayPreference? costDisplayPreference;
  @override
  final String? decisionModel;
  @override
  final LlmProvider? decisionProvider;
  @override
  final String? decisionVaultKeyId;
  @override
  final String id;
  @override
  final String? imageModel;
  @override
  final BuiltList<DocumentKind> promptKinds;
  @override
  final BuiltMap<String, String> prompts;
  @override
  final LlmProvider provider;
  @override
  final ReasoningEffortChoice? reasoningEffort;
  @override
  final bool revoked;
  @override
  final BuiltList<DocumentKind>? storedPromptKinds;
  @override
  final String userId;
  @override
  final String vaultKeyId;
  @override
  final int version;
  @override
  final String? visionModel;
  @override
  final LlmProvider? visionProvider;
  @override
  final String? visionVaultKeyId;
  @override
  final bool? visionZdrAttested;
  @override
  final bool? zdrAttested;

  factory _$AiConfigView([void Function(AiConfigViewBuilder)? updates]) =>
      (AiConfigViewBuilder()..update(updates))._build();

  _$AiConfigView._(
      {required this.assistantModel,
      this.costDisplayPreference,
      this.decisionModel,
      this.decisionProvider,
      this.decisionVaultKeyId,
      required this.id,
      this.imageModel,
      required this.promptKinds,
      required this.prompts,
      required this.provider,
      this.reasoningEffort,
      required this.revoked,
      this.storedPromptKinds,
      required this.userId,
      required this.vaultKeyId,
      required this.version,
      this.visionModel,
      this.visionProvider,
      this.visionVaultKeyId,
      this.visionZdrAttested,
      this.zdrAttested})
      : super._();
  @override
  AiConfigView rebuild(void Function(AiConfigViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiConfigViewBuilder toBuilder() => AiConfigViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiConfigView &&
        assistantModel == other.assistantModel &&
        costDisplayPreference == other.costDisplayPreference &&
        decisionModel == other.decisionModel &&
        decisionProvider == other.decisionProvider &&
        decisionVaultKeyId == other.decisionVaultKeyId &&
        id == other.id &&
        imageModel == other.imageModel &&
        promptKinds == other.promptKinds &&
        prompts == other.prompts &&
        provider == other.provider &&
        reasoningEffort == other.reasoningEffort &&
        revoked == other.revoked &&
        storedPromptKinds == other.storedPromptKinds &&
        userId == other.userId &&
        vaultKeyId == other.vaultKeyId &&
        version == other.version &&
        visionModel == other.visionModel &&
        visionProvider == other.visionProvider &&
        visionVaultKeyId == other.visionVaultKeyId &&
        visionZdrAttested == other.visionZdrAttested &&
        zdrAttested == other.zdrAttested;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, assistantModel.hashCode);
    _$hash = $jc(_$hash, costDisplayPreference.hashCode);
    _$hash = $jc(_$hash, decisionModel.hashCode);
    _$hash = $jc(_$hash, decisionProvider.hashCode);
    _$hash = $jc(_$hash, decisionVaultKeyId.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, imageModel.hashCode);
    _$hash = $jc(_$hash, promptKinds.hashCode);
    _$hash = $jc(_$hash, prompts.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, reasoningEffort.hashCode);
    _$hash = $jc(_$hash, revoked.hashCode);
    _$hash = $jc(_$hash, storedPromptKinds.hashCode);
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jc(_$hash, vaultKeyId.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jc(_$hash, visionModel.hashCode);
    _$hash = $jc(_$hash, visionProvider.hashCode);
    _$hash = $jc(_$hash, visionVaultKeyId.hashCode);
    _$hash = $jc(_$hash, visionZdrAttested.hashCode);
    _$hash = $jc(_$hash, zdrAttested.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiConfigView')
          ..add('assistantModel', assistantModel)
          ..add('costDisplayPreference', costDisplayPreference)
          ..add('decisionModel', decisionModel)
          ..add('decisionProvider', decisionProvider)
          ..add('decisionVaultKeyId', decisionVaultKeyId)
          ..add('id', id)
          ..add('imageModel', imageModel)
          ..add('promptKinds', promptKinds)
          ..add('prompts', prompts)
          ..add('provider', provider)
          ..add('reasoningEffort', reasoningEffort)
          ..add('revoked', revoked)
          ..add('storedPromptKinds', storedPromptKinds)
          ..add('userId', userId)
          ..add('vaultKeyId', vaultKeyId)
          ..add('version', version)
          ..add('visionModel', visionModel)
          ..add('visionProvider', visionProvider)
          ..add('visionVaultKeyId', visionVaultKeyId)
          ..add('visionZdrAttested', visionZdrAttested)
          ..add('zdrAttested', zdrAttested))
        .toString();
  }
}

class AiConfigViewBuilder
    implements Builder<AiConfigView, AiConfigViewBuilder> {
  _$AiConfigView? _$v;

  String? _assistantModel;
  String? get assistantModel => _$this._assistantModel;
  set assistantModel(String? assistantModel) =>
      _$this._assistantModel = assistantModel;

  CostDisplayPreference? _costDisplayPreference;
  CostDisplayPreference? get costDisplayPreference =>
      _$this._costDisplayPreference;
  set costDisplayPreference(CostDisplayPreference? costDisplayPreference) =>
      _$this._costDisplayPreference = costDisplayPreference;

  String? _decisionModel;
  String? get decisionModel => _$this._decisionModel;
  set decisionModel(String? decisionModel) =>
      _$this._decisionModel = decisionModel;

  LlmProvider? _decisionProvider;
  LlmProvider? get decisionProvider => _$this._decisionProvider;
  set decisionProvider(LlmProvider? decisionProvider) =>
      _$this._decisionProvider = decisionProvider;

  String? _decisionVaultKeyId;
  String? get decisionVaultKeyId => _$this._decisionVaultKeyId;
  set decisionVaultKeyId(String? decisionVaultKeyId) =>
      _$this._decisionVaultKeyId = decisionVaultKeyId;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _imageModel;
  String? get imageModel => _$this._imageModel;
  set imageModel(String? imageModel) => _$this._imageModel = imageModel;

  ListBuilder<DocumentKind>? _promptKinds;
  ListBuilder<DocumentKind> get promptKinds =>
      _$this._promptKinds ??= ListBuilder<DocumentKind>();
  set promptKinds(ListBuilder<DocumentKind>? promptKinds) =>
      _$this._promptKinds = promptKinds;

  MapBuilder<String, String>? _prompts;
  MapBuilder<String, String> get prompts =>
      _$this._prompts ??= MapBuilder<String, String>();
  set prompts(MapBuilder<String, String>? prompts) => _$this._prompts = prompts;

  LlmProvider? _provider;
  LlmProvider? get provider => _$this._provider;
  set provider(LlmProvider? provider) => _$this._provider = provider;

  ReasoningEffortChoice? _reasoningEffort;
  ReasoningEffortChoice? get reasoningEffort => _$this._reasoningEffort;
  set reasoningEffort(ReasoningEffortChoice? reasoningEffort) =>
      _$this._reasoningEffort = reasoningEffort;

  bool? _revoked;
  bool? get revoked => _$this._revoked;
  set revoked(bool? revoked) => _$this._revoked = revoked;

  ListBuilder<DocumentKind>? _storedPromptKinds;
  ListBuilder<DocumentKind> get storedPromptKinds =>
      _$this._storedPromptKinds ??= ListBuilder<DocumentKind>();
  set storedPromptKinds(ListBuilder<DocumentKind>? storedPromptKinds) =>
      _$this._storedPromptKinds = storedPromptKinds;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  String? _vaultKeyId;
  String? get vaultKeyId => _$this._vaultKeyId;
  set vaultKeyId(String? vaultKeyId) => _$this._vaultKeyId = vaultKeyId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  String? _visionModel;
  String? get visionModel => _$this._visionModel;
  set visionModel(String? visionModel) => _$this._visionModel = visionModel;

  LlmProvider? _visionProvider;
  LlmProvider? get visionProvider => _$this._visionProvider;
  set visionProvider(LlmProvider? visionProvider) =>
      _$this._visionProvider = visionProvider;

  String? _visionVaultKeyId;
  String? get visionVaultKeyId => _$this._visionVaultKeyId;
  set visionVaultKeyId(String? visionVaultKeyId) =>
      _$this._visionVaultKeyId = visionVaultKeyId;

  bool? _visionZdrAttested;
  bool? get visionZdrAttested => _$this._visionZdrAttested;
  set visionZdrAttested(bool? visionZdrAttested) =>
      _$this._visionZdrAttested = visionZdrAttested;

  bool? _zdrAttested;
  bool? get zdrAttested => _$this._zdrAttested;
  set zdrAttested(bool? zdrAttested) => _$this._zdrAttested = zdrAttested;

  AiConfigViewBuilder() {
    AiConfigView._defaults(this);
  }

  AiConfigViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _assistantModel = $v.assistantModel;
      _costDisplayPreference = $v.costDisplayPreference;
      _decisionModel = $v.decisionModel;
      _decisionProvider = $v.decisionProvider;
      _decisionVaultKeyId = $v.decisionVaultKeyId;
      _id = $v.id;
      _imageModel = $v.imageModel;
      _promptKinds = $v.promptKinds.toBuilder();
      _prompts = $v.prompts.toBuilder();
      _provider = $v.provider;
      _reasoningEffort = $v.reasoningEffort;
      _revoked = $v.revoked;
      _storedPromptKinds = $v.storedPromptKinds?.toBuilder();
      _userId = $v.userId;
      _vaultKeyId = $v.vaultKeyId;
      _version = $v.version;
      _visionModel = $v.visionModel;
      _visionProvider = $v.visionProvider;
      _visionVaultKeyId = $v.visionVaultKeyId;
      _visionZdrAttested = $v.visionZdrAttested;
      _zdrAttested = $v.zdrAttested;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiConfigView other) {
    _$v = other as _$AiConfigView;
  }

  @override
  void update(void Function(AiConfigViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiConfigView build() => _build();

  _$AiConfigView _build() {
    _$AiConfigView _$result;
    try {
      _$result = _$v ??
          _$AiConfigView._(
            assistantModel: BuiltValueNullFieldError.checkNotNull(
                assistantModel, r'AiConfigView', 'assistantModel'),
            costDisplayPreference: costDisplayPreference,
            decisionModel: decisionModel,
            decisionProvider: decisionProvider,
            decisionVaultKeyId: decisionVaultKeyId,
            id: BuiltValueNullFieldError.checkNotNull(
                id, r'AiConfigView', 'id'),
            imageModel: imageModel,
            promptKinds: promptKinds.build(),
            prompts: prompts.build(),
            provider: BuiltValueNullFieldError.checkNotNull(
                provider, r'AiConfigView', 'provider'),
            reasoningEffort: reasoningEffort,
            revoked: BuiltValueNullFieldError.checkNotNull(
                revoked, r'AiConfigView', 'revoked'),
            storedPromptKinds: _storedPromptKinds?.build(),
            userId: BuiltValueNullFieldError.checkNotNull(
                userId, r'AiConfigView', 'userId'),
            vaultKeyId: BuiltValueNullFieldError.checkNotNull(
                vaultKeyId, r'AiConfigView', 'vaultKeyId'),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'AiConfigView', 'version'),
            visionModel: visionModel,
            visionProvider: visionProvider,
            visionVaultKeyId: visionVaultKeyId,
            visionZdrAttested: visionZdrAttested,
            zdrAttested: zdrAttested,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'promptKinds';
        promptKinds.build();
        _$failedField = 'prompts';
        prompts.build();

        _$failedField = 'storedPromptKinds';
        _storedPromptKinds?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AiConfigView', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
