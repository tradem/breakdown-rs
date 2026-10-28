// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_piece.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DraftPiece extends DraftPiece {
  @override
  final String? categoryHint;
  @override
  final String? description;
  @override
  final String name;

  factory _$DraftPiece([void Function(DraftPieceBuilder)? updates]) =>
      (DraftPieceBuilder()..update(updates))._build();

  _$DraftPiece._({this.categoryHint, this.description, required this.name})
      : super._();
  @override
  DraftPiece rebuild(void Function(DraftPieceBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DraftPieceBuilder toBuilder() => DraftPieceBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DraftPiece &&
        categoryHint == other.categoryHint &&
        description == other.description &&
        name == other.name;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, categoryHint.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DraftPiece')
          ..add('categoryHint', categoryHint)
          ..add('description', description)
          ..add('name', name))
        .toString();
  }
}

class DraftPieceBuilder implements Builder<DraftPiece, DraftPieceBuilder> {
  _$DraftPiece? _$v;

  String? _categoryHint;
  String? get categoryHint => _$this._categoryHint;
  set categoryHint(String? categoryHint) => _$this._categoryHint = categoryHint;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  DraftPieceBuilder() {
    DraftPiece._defaults(this);
  }

  DraftPieceBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _categoryHint = $v.categoryHint;
      _description = $v.description;
      _name = $v.name;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DraftPiece other) {
    _$v = other as _$DraftPiece;
  }

  @override
  void update(void Function(DraftPieceBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DraftPiece build() => _build();

  _$DraftPiece _build() {
    final _$result = _$v ??
        _$DraftPiece._(
          categoryHint: categoryHint,
          description: description,
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'DraftPiece', 'name'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
