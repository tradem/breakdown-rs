// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'piece_detail_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PieceDetailRequest extends PieceDetailRequest {
  @override
  final String id;
  @override
  final String? subject;
  @override
  final String text;

  factory _$PieceDetailRequest(
          [void Function(PieceDetailRequestBuilder)? updates]) =>
      (PieceDetailRequestBuilder()..update(updates))._build();

  _$PieceDetailRequest._({required this.id, this.subject, required this.text})
      : super._();
  @override
  PieceDetailRequest rebuild(
          void Function(PieceDetailRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PieceDetailRequestBuilder toBuilder() =>
      PieceDetailRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PieceDetailRequest &&
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
    return (newBuiltValueToStringHelper(r'PieceDetailRequest')
          ..add('id', id)
          ..add('subject', subject)
          ..add('text', text))
        .toString();
  }
}

class PieceDetailRequestBuilder
    implements Builder<PieceDetailRequest, PieceDetailRequestBuilder> {
  _$PieceDetailRequest? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _subject;
  String? get subject => _$this._subject;
  set subject(String? subject) => _$this._subject = subject;

  String? _text;
  String? get text => _$this._text;
  set text(String? text) => _$this._text = text;

  PieceDetailRequestBuilder() {
    PieceDetailRequest._defaults(this);
  }

  PieceDetailRequestBuilder get _$this {
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
  void replace(PieceDetailRequest other) {
    _$v = other as _$PieceDetailRequest;
  }

  @override
  void update(void Function(PieceDetailRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PieceDetailRequest build() => _build();

  _$PieceDetailRequest _build() {
    final _$result = _$v ??
        _$PieceDetailRequest._(
          id: BuiltValueNullFieldError.checkNotNull(
              id, r'PieceDetailRequest', 'id'),
          subject: subject,
          text: BuiltValueNullFieldError.checkNotNull(
              text, r'PieceDetailRequest', 'text'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
