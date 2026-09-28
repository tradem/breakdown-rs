// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'costume_detail_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CostumeDetailRequest extends CostumeDetailRequest {
  @override
  final String id;
  @override
  final String? subject;
  @override
  final String text;

  factory _$CostumeDetailRequest(
          [void Function(CostumeDetailRequestBuilder)? updates]) =>
      (CostumeDetailRequestBuilder()..update(updates))._build();

  _$CostumeDetailRequest._({required this.id, this.subject, required this.text})
      : super._();
  @override
  CostumeDetailRequest rebuild(
          void Function(CostumeDetailRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CostumeDetailRequestBuilder toBuilder() =>
      CostumeDetailRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CostumeDetailRequest &&
        id == other.id &&
        subject == other.subject &&
        text == other.text;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, subject.hashCode);
    _$hash = $jc(_$hash, text.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CostumeDetailRequest')
          ..add('id', id)
          ..add('subject', subject)
          ..add('text', text))
        .toString();
  }
}

class CostumeDetailRequestBuilder
    implements Builder<CostumeDetailRequest, CostumeDetailRequestBuilder> {
  _$CostumeDetailRequest? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _subject;
  String? get subject => _$this._subject;
  set subject(String? subject) => _$this._subject = subject;

  String? _text;
  String? get text => _$this._text;
  set text(String? text) => _$this._text = text;

  CostumeDetailRequestBuilder() {
    CostumeDetailRequest._defaults(this);
  }

  CostumeDetailRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _subject = $v.subject;
      _text = $v.text;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CostumeDetailRequest other) {
    _$v = other as _$CostumeDetailRequest;
  }

  @override
  void update(void Function(CostumeDetailRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CostumeDetailRequest build() => _build();

  _$CostumeDetailRequest _build() {
    final _$result = _$v ??
        _$CostumeDetailRequest._(
          id: BuiltValueNullFieldError.checkNotNull(
              id, r'CostumeDetailRequest', 'id'),
          subject: subject,
          text: BuiltValueNullFieldError.checkNotNull(
              text, r'CostumeDetailRequest', 'text'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
