// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'piece_detail_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PieceDetailView extends PieceDetailView {
  @override
  final String id;
  @override
  final String? subject;
  @override
  final String text;

  factory _$PieceDetailView([void Function(PieceDetailViewBuilder)? updates]) =>
      (PieceDetailViewBuilder()..update(updates))._build();

  _$PieceDetailView._({required this.id, this.subject, required this.text})
      : super._();
  @override
  PieceDetailView rebuild(void Function(PieceDetailViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PieceDetailViewBuilder toBuilder() => PieceDetailViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PieceDetailView &&
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
    return (newBuiltValueToStringHelper(r'PieceDetailView')
          ..add('id', id)
          ..add('subject', subject)
          ..add('text', text))
        .toString();
  }
}

class PieceDetailViewBuilder
    implements Builder<PieceDetailView, PieceDetailViewBuilder> {
  _$PieceDetailView? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _subject;
  String? get subject => _$this._subject;
  set subject(String? subject) => _$this._subject = subject;

  String? _text;
  String? get text => _$this._text;
  set text(String? text) => _$this._text = text;

  PieceDetailViewBuilder() {
    PieceDetailView._defaults(this);
  }

  PieceDetailViewBuilder get _$this {
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
  void replace(PieceDetailView other) {
    _$v = other as _$PieceDetailView;
  }

  @override
  void update(void Function(PieceDetailViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PieceDetailView build() => _build();

  _$PieceDetailView _build() {
    final _$result = _$v ??
        _$PieceDetailView._(
          id: BuiltValueNullFieldError.checkNotNull(
              id, r'PieceDetailView', 'id'),
          subject: subject,
          text: BuiltValueNullFieldError.checkNotNull(
              text, r'PieceDetailView', 'text'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
