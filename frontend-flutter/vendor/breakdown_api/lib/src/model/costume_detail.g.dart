// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'costume_detail.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CostumeDetail extends CostumeDetail {
  @override
  final String? categoryId;
  @override
  final String id;
  @override
  final String? subject;
  @override
  final String text;

  factory _$CostumeDetail([void Function(CostumeDetailBuilder)? updates]) =>
      (CostumeDetailBuilder()..update(updates))._build();

  _$CostumeDetail._(
      {this.categoryId, required this.id, this.subject, required this.text})
      : super._();
  @override
  CostumeDetail rebuild(void Function(CostumeDetailBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CostumeDetailBuilder toBuilder() => CostumeDetailBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CostumeDetail &&
        categoryId == other.categoryId &&
        id == other.id &&
        subject == other.subject &&
        text == other.text;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, categoryId.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, subject.hashCode);
    _$hash = $jc(_$hash, text.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CostumeDetail')
          ..add('categoryId', categoryId)
          ..add('id', id)
          ..add('subject', subject)
          ..add('text', text))
        .toString();
  }
}

class CostumeDetailBuilder
    implements Builder<CostumeDetail, CostumeDetailBuilder> {
  _$CostumeDetail? _$v;

  String? _categoryId;
  String? get categoryId => _$this._categoryId;
  set categoryId(String? categoryId) => _$this._categoryId = categoryId;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _subject;
  String? get subject => _$this._subject;
  set subject(String? subject) => _$this._subject = subject;

  String? _text;
  String? get text => _$this._text;
  set text(String? text) => _$this._text = text;

  CostumeDetailBuilder() {
    CostumeDetail._defaults(this);
  }

  CostumeDetailBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _categoryId = $v.categoryId;
      _id = $v.id;
      _subject = $v.subject;
      _text = $v.text;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CostumeDetail other) {
    _$v = other as _$CostumeDetail;
  }

  @override
  void update(void Function(CostumeDetailBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CostumeDetail build() => _build();

  _$CostumeDetail _build() {
    final _$result = _$v ??
        _$CostumeDetail._(
          categoryId: categoryId,
          id: BuiltValueNullFieldError.checkNotNull(id, r'CostumeDetail', 'id'),
          subject: subject,
          text: BuiltValueNullFieldError.checkNotNull(
              text, r'CostumeDetail', 'text'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
