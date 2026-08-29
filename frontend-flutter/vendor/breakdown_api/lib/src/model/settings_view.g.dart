// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SettingsView extends SettingsView {
  @override
  final CredentialBindingState bindingState;
  @override
  final String id;
  @override
  final String provider;
  @override
  final String vaultKeyId;
  @override
  final int vaultVersion;
  @override
  final int version;

  factory _$SettingsView([void Function(SettingsViewBuilder)? updates]) =>
      (SettingsViewBuilder()..update(updates))._build();

  _$SettingsView._(
      {required this.bindingState,
      required this.id,
      required this.provider,
      required this.vaultKeyId,
      required this.vaultVersion,
      required this.version})
      : super._();
  @override
  SettingsView rebuild(void Function(SettingsViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SettingsViewBuilder toBuilder() => SettingsViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SettingsView &&
        bindingState == other.bindingState &&
        id == other.id &&
        provider == other.provider &&
        vaultKeyId == other.vaultKeyId &&
        vaultVersion == other.vaultVersion &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bindingState.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, vaultKeyId.hashCode);
    _$hash = $jc(_$hash, vaultVersion.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SettingsView')
          ..add('bindingState', bindingState)
          ..add('id', id)
          ..add('provider', provider)
          ..add('vaultKeyId', vaultKeyId)
          ..add('vaultVersion', vaultVersion)
          ..add('version', version))
        .toString();
  }
}

class SettingsViewBuilder
    implements Builder<SettingsView, SettingsViewBuilder> {
  _$SettingsView? _$v;

  CredentialBindingState? _bindingState;
  CredentialBindingState? get bindingState => _$this._bindingState;
  set bindingState(CredentialBindingState? bindingState) =>
      _$this._bindingState = bindingState;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _provider;
  String? get provider => _$this._provider;
  set provider(String? provider) => _$this._provider = provider;

  String? _vaultKeyId;
  String? get vaultKeyId => _$this._vaultKeyId;
  set vaultKeyId(String? vaultKeyId) => _$this._vaultKeyId = vaultKeyId;

  int? _vaultVersion;
  int? get vaultVersion => _$this._vaultVersion;
  set vaultVersion(int? vaultVersion) => _$this._vaultVersion = vaultVersion;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  SettingsViewBuilder() {
    SettingsView._defaults(this);
  }

  SettingsViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bindingState = $v.bindingState;
      _id = $v.id;
      _provider = $v.provider;
      _vaultKeyId = $v.vaultKeyId;
      _vaultVersion = $v.vaultVersion;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SettingsView other) {
    _$v = other as _$SettingsView;
  }

  @override
  void update(void Function(SettingsViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SettingsView build() => _build();

  _$SettingsView _build() {
    final _$result = _$v ??
        _$SettingsView._(
          bindingState: BuiltValueNullFieldError.checkNotNull(
              bindingState, r'SettingsView', 'bindingState'),
          id: BuiltValueNullFieldError.checkNotNull(id, r'SettingsView', 'id'),
          provider: BuiltValueNullFieldError.checkNotNull(
              provider, r'SettingsView', 'provider'),
          vaultKeyId: BuiltValueNullFieldError.checkNotNull(
              vaultKeyId, r'SettingsView', 'vaultKeyId'),
          vaultVersion: BuiltValueNullFieldError.checkNotNull(
              vaultVersion, r'SettingsView', 'vaultVersion'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'SettingsView', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
