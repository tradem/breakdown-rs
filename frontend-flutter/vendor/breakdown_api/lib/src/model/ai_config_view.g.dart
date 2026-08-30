// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_config_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiConfigView extends AiConfigView {
  @override
  final String assistantModel;
  @override
  final String id;
  @override
  final String? imageModel;
  @override
  final BuiltList<DocumentKind> promptKinds;
  @override
  final LlmProvider provider;
  @override
  final bool revoked;
  @override
  final String userId;
  @override
  final String vaultKeyId;
  @override
  final int version;

  factory _$AiConfigView([void Function(AiConfigViewBuilder)? updates]) =>
      (AiConfigViewBuilder()..update(updates))._build();

  _$AiConfigView._(
      {required this.assistantModel,
      required this.id,
      this.imageModel,
      required this.promptKinds,
      required this.provider,
      required this.revoked,
      required this.userId,
      required this.vaultKeyId,
      required this.version})
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
        id == other.id &&
        imageModel == other.imageModel &&
        promptKinds == other.promptKinds &&
        provider == other.provider &&
        revoked == other.revoked &&
        userId == other.userId &&
        vaultKeyId == other.vaultKeyId &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, assistantModel.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, imageModel.hashCode);
    _$hash = $jc(_$hash, promptKinds.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, revoked.hashCode);
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jc(_$hash, vaultKeyId.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiConfigView')
          ..add('assistantModel', assistantModel)
          ..add('id', id)
          ..add('imageModel', imageModel)
          ..add('promptKinds', promptKinds)
          ..add('provider', provider)
          ..add('revoked', revoked)
          ..add('userId', userId)
          ..add('vaultKeyId', vaultKeyId)
          ..add('version', version))
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

  LlmProvider? _provider;
  LlmProvider? get provider => _$this._provider;
  set provider(LlmProvider? provider) => _$this._provider = provider;

  bool? _revoked;
  bool? get revoked => _$this._revoked;
  set revoked(bool? revoked) => _$this._revoked = revoked;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  String? _vaultKeyId;
  String? get vaultKeyId => _$this._vaultKeyId;
  set vaultKeyId(String? vaultKeyId) => _$this._vaultKeyId = vaultKeyId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  AiConfigViewBuilder() {
    AiConfigView._defaults(this);
  }

  AiConfigViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _assistantModel = $v.assistantModel;
      _id = $v.id;
      _imageModel = $v.imageModel;
      _promptKinds = $v.promptKinds.toBuilder();
      _provider = $v.provider;
      _revoked = $v.revoked;
      _userId = $v.userId;
      _vaultKeyId = $v.vaultKeyId;
      _version = $v.version;
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
            id: BuiltValueNullFieldError.checkNotNull(
                id, r'AiConfigView', 'id'),
            imageModel: imageModel,
            promptKinds: promptKinds.build(),
            provider: BuiltValueNullFieldError.checkNotNull(
                provider, r'AiConfigView', 'provider'),
            revoked: BuiltValueNullFieldError.checkNotNull(
                revoked, r'AiConfigView', 'revoked'),
            userId: BuiltValueNullFieldError.checkNotNull(
                userId, r'AiConfigView', 'userId'),
            vaultKeyId: BuiltValueNullFieldError.checkNotNull(
                vaultKeyId, r'AiConfigView', 'vaultKeyId'),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'AiConfigView', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'promptKinds';
        promptKinds.build();
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
