// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outfit_piece_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OutfitPieceView extends OutfitPieceView {
  @override
  final String? categoryId;
  @override
  final String? categoryName;
  @override
  final String? name;
  @override
  final String pieceId;
  @override
  final int position;

  factory _$OutfitPieceView([void Function(OutfitPieceViewBuilder)? updates]) =>
      (OutfitPieceViewBuilder()..update(updates))._build();

  _$OutfitPieceView._(
      {this.categoryId,
      this.categoryName,
      this.name,
      required this.pieceId,
      required this.position})
      : super._();
  @override
  OutfitPieceView rebuild(void Function(OutfitPieceViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OutfitPieceViewBuilder toBuilder() => OutfitPieceViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OutfitPieceView &&
        categoryId == other.categoryId &&
        categoryName == other.categoryName &&
        name == other.name &&
        pieceId == other.pieceId &&
        position == other.position;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, categoryId.hashCode);
    _$hash = $jc(_$hash, categoryName.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, pieceId.hashCode);
    _$hash = $jc(_$hash, position.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OutfitPieceView')
          ..add('categoryId', categoryId)
          ..add('categoryName', categoryName)
          ..add('name', name)
          ..add('pieceId', pieceId)
          ..add('position', position))
        .toString();
  }
}

class OutfitPieceViewBuilder
    implements Builder<OutfitPieceView, OutfitPieceViewBuilder> {
  _$OutfitPieceView? _$v;

  String? _categoryId;
  String? get categoryId => _$this._categoryId;
  set categoryId(String? categoryId) => _$this._categoryId = categoryId;

  String? _categoryName;
  String? get categoryName => _$this._categoryName;
  set categoryName(String? categoryName) => _$this._categoryName = categoryName;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _pieceId;
  String? get pieceId => _$this._pieceId;
  set pieceId(String? pieceId) => _$this._pieceId = pieceId;

  int? _position;
  int? get position => _$this._position;
  set position(int? position) => _$this._position = position;

  OutfitPieceViewBuilder() {
    OutfitPieceView._defaults(this);
  }

  OutfitPieceViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _categoryId = $v.categoryId;
      _categoryName = $v.categoryName;
      _name = $v.name;
      _pieceId = $v.pieceId;
      _position = $v.position;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OutfitPieceView other) {
    _$v = other as _$OutfitPieceView;
  }

  @override
  void update(void Function(OutfitPieceViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OutfitPieceView build() => _build();

  _$OutfitPieceView _build() {
    final _$result = _$v ??
        _$OutfitPieceView._(
          categoryId: categoryId,
          categoryName: categoryName,
          name: name,
          pieceId: BuiltValueNullFieldError.checkNotNull(
              pieceId, r'OutfitPieceView', 'pieceId'),
          position: BuiltValueNullFieldError.checkNotNull(
              position, r'OutfitPieceView', 'position'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
