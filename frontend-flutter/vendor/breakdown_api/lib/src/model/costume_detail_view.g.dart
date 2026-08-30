// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'costume_detail_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CostumeDetailView extends CostumeDetailView {
  @override
  final String? categoryId;
  @override
  final String? categoryName;
  @override
  final String id;
  @override
  final String? subject;
  @override
  final String text;

  factory _$CostumeDetailView(
          [void Function(CostumeDetailViewBuilder)? updates]) =>
      (CostumeDetailViewBuilder()..update(updates))._build();

  _$CostumeDetailView._(
      {this.categoryId,
      this.categoryName,
      required this.id,
      this.subject,
      required this.text})
      : super._();
  @override
  CostumeDetailView rebuild(void Function(CostumeDetailViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CostumeDetailViewBuilder toBuilder() =>
      CostumeDetailViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CostumeDetailView &&
        categoryId == other.categoryId &&
        categoryName == other.categoryName &&
        id == other.id &&
        subject == other.subject &&
        text == other.text;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, categoryId.hashCode);
    _$hash = $jc(_$hash, categoryName.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, subject.hashCode);
    _$hash = $jc(_$hash, text.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CostumeDetailView')
          ..add('categoryId', categoryId)
          ..add('categoryName', categoryName)
          ..add('id', id)
          ..add('subject', subject)
          ..add('text', text))
        .toString();
  }
}

class CostumeDetailViewBuilder
    implements Builder<CostumeDetailView, CostumeDetailViewBuilder> {
  _$CostumeDetailView? _$v;

  String? _categoryId;
  String? get categoryId => _$this._categoryId;
  set categoryId(String? categoryId) => _$this._categoryId = categoryId;

  String? _categoryName;
  String? get categoryName => _$this._categoryName;
  set categoryName(String? categoryName) => _$this._categoryName = categoryName;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _subject;
  String? get subject => _$this._subject;
  set subject(String? subject) => _$this._subject = subject;

  String? _text;
  String? get text => _$this._text;
  set text(String? text) => _$this._text = text;

  CostumeDetailViewBuilder() {
    CostumeDetailView._defaults(this);
  }

  CostumeDetailViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _categoryId = $v.categoryId;
      _categoryName = $v.categoryName;
      _id = $v.id;
      _subject = $v.subject;
      _text = $v.text;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CostumeDetailView other) {
    _$v = other as _$CostumeDetailView;
  }

  @override
  void update(void Function(CostumeDetailViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CostumeDetailView build() => _build();

  _$CostumeDetailView _build() {
    final _$result = _$v ??
        _$CostumeDetailView._(
          categoryId: categoryId,
          categoryName: categoryName,
          id: BuiltValueNullFieldError.checkNotNull(
              id, r'CostumeDetailView', 'id'),
          subject: subject,
          text: BuiltValueNullFieldError.checkNotNull(
              text, r'CostumeDetailView', 'text'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
