// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_credential_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateCredentialRequest extends CreateCredentialRequest {
  @override
  final String provider;
  @override
  final String secret;

  factory _$CreateCredentialRequest(
          [void Function(CreateCredentialRequestBuilder)? updates]) =>
      (CreateCredentialRequestBuilder()..update(updates))._build();

  _$CreateCredentialRequest._({required this.provider, required this.secret})
      : super._();
  @override
  CreateCredentialRequest rebuild(
          void Function(CreateCredentialRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateCredentialRequestBuilder toBuilder() =>
      CreateCredentialRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateCredentialRequest &&
        provider == other.provider &&
        secret == other.secret;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, secret.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateCredentialRequest')
          ..add('provider', provider)
          ..add('secret', secret))
        .toString();
  }
}

class CreateCredentialRequestBuilder
    implements
        Builder<CreateCredentialRequest, CreateCredentialRequestBuilder> {
  _$CreateCredentialRequest? _$v;

  String? _provider;
  String? get provider => _$this._provider;
  set provider(String? provider) => _$this._provider = provider;

  String? _secret;
  String? get secret => _$this._secret;
  set secret(String? secret) => _$this._secret = secret;

  CreateCredentialRequestBuilder() {
    CreateCredentialRequest._defaults(this);
  }

  CreateCredentialRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _provider = $v.provider;
      _secret = $v.secret;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateCredentialRequest other) {
    _$v = other as _$CreateCredentialRequest;
  }

  @override
  void update(void Function(CreateCredentialRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateCredentialRequest build() => _build();

  _$CreateCredentialRequest _build() {
    final _$result = _$v ??
        _$CreateCredentialRequest._(
          provider: BuiltValueNullFieldError.checkNotNull(
              provider, r'CreateCredentialRequest', 'provider'),
          secret: BuiltValueNullFieldError.checkNotNull(
              secret, r'CreateCredentialRequest', 'secret'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
