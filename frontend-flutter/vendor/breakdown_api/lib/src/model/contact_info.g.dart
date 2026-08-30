// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contact_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ContactInfo extends ContactInfo {
  @override
  final String? email;
  @override
  final String? phone;

  factory _$ContactInfo([void Function(ContactInfoBuilder)? updates]) =>
      (ContactInfoBuilder()..update(updates))._build();

  _$ContactInfo._({this.email, this.phone}) : super._();
  @override
  ContactInfo rebuild(void Function(ContactInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ContactInfoBuilder toBuilder() => ContactInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ContactInfo && email == other.email && phone == other.phone;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, phone.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ContactInfo')
          ..add('email', email)
          ..add('phone', phone))
        .toString();
  }
}

class ContactInfoBuilder implements Builder<ContactInfo, ContactInfoBuilder> {
  _$ContactInfo? _$v;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

  String? _phone;
  String? get phone => _$this._phone;
  set phone(String? phone) => _$this._phone = phone;

  ContactInfoBuilder() {
    ContactInfo._defaults(this);
  }

  ContactInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _email = $v.email;
      _phone = $v.phone;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ContactInfo other) {
    _$v = other as _$ContactInfo;
  }

  @override
  void update(void Function(ContactInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ContactInfo build() => _build();

  _$ContactInfo _build() {
    final _$result = _$v ??
        _$ContactInfo._(
          email: email,
          phone: phone,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
