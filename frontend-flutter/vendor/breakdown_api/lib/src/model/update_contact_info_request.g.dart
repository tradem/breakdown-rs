// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_contact_info_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateContactInfoRequest extends UpdateContactInfoRequest {
  @override
  final ContactInfo contactInfo;
  @override
  final int version;

  factory _$UpdateContactInfoRequest(
          [void Function(UpdateContactInfoRequestBuilder)? updates]) =>
      (UpdateContactInfoRequestBuilder()..update(updates))._build();

  _$UpdateContactInfoRequest._(
      {required this.contactInfo, required this.version})
      : super._();
  @override
  UpdateContactInfoRequest rebuild(
          void Function(UpdateContactInfoRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateContactInfoRequestBuilder toBuilder() =>
      UpdateContactInfoRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateContactInfoRequest &&
        contactInfo == other.contactInfo &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, contactInfo.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateContactInfoRequest')
          ..add('contactInfo', contactInfo)
          ..add('version', version))
        .toString();
  }
}

class UpdateContactInfoRequestBuilder
    implements
        Builder<UpdateContactInfoRequest, UpdateContactInfoRequestBuilder> {
  _$UpdateContactInfoRequest? _$v;

  ContactInfoBuilder? _contactInfo;
  ContactInfoBuilder get contactInfo =>
      _$this._contactInfo ??= ContactInfoBuilder();
  set contactInfo(ContactInfoBuilder? contactInfo) =>
      _$this._contactInfo = contactInfo;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdateContactInfoRequestBuilder() {
    UpdateContactInfoRequest._defaults(this);
  }

  UpdateContactInfoRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _contactInfo = $v.contactInfo.toBuilder();
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateContactInfoRequest other) {
    _$v = other as _$UpdateContactInfoRequest;
  }

  @override
  void update(void Function(UpdateContactInfoRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateContactInfoRequest build() => _build();

  _$UpdateContactInfoRequest _build() {
    _$UpdateContactInfoRequest _$result;
    try {
      _$result = _$v ??
          _$UpdateContactInfoRequest._(
            contactInfo: contactInfo.build(),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'UpdateContactInfoRequest', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'contactInfo';
        contactInfo.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'UpdateContactInfoRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
