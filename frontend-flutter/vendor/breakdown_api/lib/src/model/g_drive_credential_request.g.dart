// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'g_drive_credential_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

abstract class GDriveCredentialRequestBuilder {
  void replace(GDriveCredentialRequest other);
  void update(void Function(GDriveCredentialRequestBuilder) updates);
  String? get clientId;
  set clientId(String? clientId);

  String? get clientSecret;
  set clientSecret(String? clientSecret);

  String? get refreshToken;
  set refreshToken(String? refreshToken);

  String? get rootFolderId;
  set rootFolderId(String? rootFolderId);
}

class _$$GDriveCredentialRequest extends $GDriveCredentialRequest {
  @override
  final String clientId;
  @override
  final String clientSecret;
  @override
  final String refreshToken;
  @override
  final String? rootFolderId;

  factory _$$GDriveCredentialRequest(
          [void Function($GDriveCredentialRequestBuilder)? updates]) =>
      ($GDriveCredentialRequestBuilder()..update(updates))._build();

  _$$GDriveCredentialRequest._(
      {required this.clientId,
      required this.clientSecret,
      required this.refreshToken,
      this.rootFolderId})
      : super._();
  @override
  $GDriveCredentialRequest rebuild(
          void Function($GDriveCredentialRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  $GDriveCredentialRequestBuilder toBuilder() =>
      $GDriveCredentialRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is $GDriveCredentialRequest &&
        clientId == other.clientId &&
        clientSecret == other.clientSecret &&
        refreshToken == other.refreshToken &&
        rootFolderId == other.rootFolderId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, clientId.hashCode);
    _$hash = $jc(_$hash, clientSecret.hashCode);
    _$hash = $jc(_$hash, refreshToken.hashCode);
    _$hash = $jc(_$hash, rootFolderId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'$GDriveCredentialRequest')
          ..add('clientId', clientId)
          ..add('clientSecret', clientSecret)
          ..add('refreshToken', refreshToken)
          ..add('rootFolderId', rootFolderId))
        .toString();
  }
}

class $GDriveCredentialRequestBuilder
    implements
        Builder<$GDriveCredentialRequest, $GDriveCredentialRequestBuilder>,
        GDriveCredentialRequestBuilder {
  _$$GDriveCredentialRequest? _$v;

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

  $GDriveCredentialRequestBuilder() {
    $GDriveCredentialRequest._defaults(this);
  }

  $GDriveCredentialRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _clientId = $v.clientId;
      _clientSecret = $v.clientSecret;
      _refreshToken = $v.refreshToken;
      _rootFolderId = $v.rootFolderId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant $GDriveCredentialRequest other) {
    _$v = other as _$$GDriveCredentialRequest;
  }

  @override
  void update(void Function($GDriveCredentialRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  $GDriveCredentialRequest build() => _build();

  _$$GDriveCredentialRequest _build() {
    final _$result = _$v ??
        _$$GDriveCredentialRequest._(
          clientId: BuiltValueNullFieldError.checkNotNull(
              clientId, r'$GDriveCredentialRequest', 'clientId'),
          clientSecret: BuiltValueNullFieldError.checkNotNull(
              clientSecret, r'$GDriveCredentialRequest', 'clientSecret'),
          refreshToken: BuiltValueNullFieldError.checkNotNull(
              refreshToken, r'$GDriveCredentialRequest', 'refreshToken'),
          rootFolderId: rootFolderId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
