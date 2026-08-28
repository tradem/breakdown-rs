// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'g_drive_credential_update_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GDriveCredentialUpdateRequest extends GDriveCredentialUpdateRequest {
  @override
  final int version;
  @override
  final String clientId;
  @override
  final String clientSecret;
  @override
  final String refreshToken;
  @override
  final String? rootFolderId;

  factory _$GDriveCredentialUpdateRequest(
          [void Function(GDriveCredentialUpdateRequestBuilder)? updates]) =>
      (GDriveCredentialUpdateRequestBuilder()..update(updates))._build();

  _$GDriveCredentialUpdateRequest._(
      {required this.version,
      required this.clientId,
      required this.clientSecret,
      required this.refreshToken,
      this.rootFolderId})
      : super._();
  @override
  GDriveCredentialUpdateRequest rebuild(
          void Function(GDriveCredentialUpdateRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GDriveCredentialUpdateRequestBuilder toBuilder() =>
      GDriveCredentialUpdateRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GDriveCredentialUpdateRequest &&
        version == other.version &&
        clientId == other.clientId &&
        clientSecret == other.clientSecret &&
        refreshToken == other.refreshToken &&
        rootFolderId == other.rootFolderId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jc(_$hash, clientId.hashCode);
    _$hash = $jc(_$hash, clientSecret.hashCode);
    _$hash = $jc(_$hash, refreshToken.hashCode);
    _$hash = $jc(_$hash, rootFolderId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GDriveCredentialUpdateRequest')
          ..add('version', version)
          ..add('clientId', clientId)
          ..add('clientSecret', clientSecret)
          ..add('refreshToken', refreshToken)
          ..add('rootFolderId', rootFolderId))
        .toString();
  }
}

class GDriveCredentialUpdateRequestBuilder
    implements
        Builder<GDriveCredentialUpdateRequest,
            GDriveCredentialUpdateRequestBuilder>,
        GDriveCredentialRequestBuilder {
  _$GDriveCredentialUpdateRequest? _$v;

  int? _version;
  int? get version => _$this._version;
  set version(covariant int? version) => _$this._version = version;

  String? _clientId;
  String? get clientId => _$this._clientId;
  set clientId(covariant String? clientId) => _$this._clientId = clientId;

  String? _clientSecret;
  String? get clientSecret => _$this._clientSecret;
  set clientSecret(covariant String? clientSecret) =>
      _$this._clientSecret = clientSecret;

  String? _refreshToken;
  String? get refreshToken => _$this._refreshToken;
  set refreshToken(covariant String? refreshToken) =>
      _$this._refreshToken = refreshToken;

  String? _rootFolderId;
  String? get rootFolderId => _$this._rootFolderId;
  set rootFolderId(covariant String? rootFolderId) =>
      _$this._rootFolderId = rootFolderId;

  GDriveCredentialUpdateRequestBuilder() {
    GDriveCredentialUpdateRequest._defaults(this);
  }

  GDriveCredentialUpdateRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _version = $v.version;
      _clientId = $v.clientId;
      _clientSecret = $v.clientSecret;
      _refreshToken = $v.refreshToken;
      _rootFolderId = $v.rootFolderId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant GDriveCredentialUpdateRequest other) {
    _$v = other as _$GDriveCredentialUpdateRequest;
  }

  @override
  void update(void Function(GDriveCredentialUpdateRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GDriveCredentialUpdateRequest build() => _build();

  _$GDriveCredentialUpdateRequest _build() {
    final _$result = _$v ??
        _$GDriveCredentialUpdateRequest._(
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'GDriveCredentialUpdateRequest', 'version'),
          clientId: BuiltValueNullFieldError.checkNotNull(
              clientId, r'GDriveCredentialUpdateRequest', 'clientId'),
          clientSecret: BuiltValueNullFieldError.checkNotNull(
              clientSecret, r'GDriveCredentialUpdateRequest', 'clientSecret'),
          refreshToken: BuiltValueNullFieldError.checkNotNull(
              refreshToken, r'GDriveCredentialUpdateRequest', 'refreshToken'),
          rootFolderId: rootFolderId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
