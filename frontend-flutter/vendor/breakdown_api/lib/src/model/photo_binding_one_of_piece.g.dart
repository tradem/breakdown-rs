// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_binding_one_of_piece.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhotoBindingOneOfPiece extends PhotoBindingOneOfPiece {
  @override
  final String pieceId;

  factory _$PhotoBindingOneOfPiece(
          [void Function(PhotoBindingOneOfPieceBuilder)? updates]) =>
      (PhotoBindingOneOfPieceBuilder()..update(updates))._build();

  _$PhotoBindingOneOfPiece._({required this.pieceId}) : super._();
  @override
  PhotoBindingOneOfPiece rebuild(
          void Function(PhotoBindingOneOfPieceBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhotoBindingOneOfPieceBuilder toBuilder() =>
      PhotoBindingOneOfPieceBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhotoBindingOneOfPiece && pieceId == other.pieceId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pieceId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhotoBindingOneOfPiece')
          ..add('pieceId', pieceId))
        .toString();
  }
}

class PhotoBindingOneOfPieceBuilder
    implements Builder<PhotoBindingOneOfPiece, PhotoBindingOneOfPieceBuilder> {
  _$PhotoBindingOneOfPiece? _$v;

  String? _pieceId;
  String? get pieceId => _$this._pieceId;
  set pieceId(String? pieceId) => _$this._pieceId = pieceId;

  PhotoBindingOneOfPieceBuilder() {
    PhotoBindingOneOfPiece._defaults(this);
  }

  PhotoBindingOneOfPieceBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pieceId = $v.pieceId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhotoBindingOneOfPiece other) {
    _$v = other as _$PhotoBindingOneOfPiece;
  }

  @override
  void update(void Function(PhotoBindingOneOfPieceBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhotoBindingOneOfPiece build() => _build();

  _$PhotoBindingOneOfPiece _build() {
    final _$result = _$v ??
        _$PhotoBindingOneOfPiece._(
          pieceId: BuiltValueNullFieldError.checkNotNull(
              pieceId, r'PhotoBindingOneOfPiece', 'pieceId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
