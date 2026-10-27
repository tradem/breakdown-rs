// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_binding_one_of.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhotoBindingOneOf extends PhotoBindingOneOf {
  @override
  final PhotoBindingOneOfPiece piece;

  factory _$PhotoBindingOneOf(
          [void Function(PhotoBindingOneOfBuilder)? updates]) =>
      (PhotoBindingOneOfBuilder()..update(updates))._build();

  _$PhotoBindingOneOf._({required this.piece}) : super._();
  @override
  PhotoBindingOneOf rebuild(void Function(PhotoBindingOneOfBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhotoBindingOneOfBuilder toBuilder() =>
      PhotoBindingOneOfBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhotoBindingOneOf && piece == other.piece;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, piece.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhotoBindingOneOf')
          ..add('piece', piece))
        .toString();
  }
}

class PhotoBindingOneOfBuilder
    implements Builder<PhotoBindingOneOf, PhotoBindingOneOfBuilder> {
  _$PhotoBindingOneOf? _$v;

  PhotoBindingOneOfPieceBuilder? _piece;
  PhotoBindingOneOfPieceBuilder get piece =>
      _$this._piece ??= PhotoBindingOneOfPieceBuilder();
  set piece(PhotoBindingOneOfPieceBuilder? piece) => _$this._piece = piece;

  PhotoBindingOneOfBuilder() {
    PhotoBindingOneOf._defaults(this);
  }

  PhotoBindingOneOfBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _piece = $v.piece.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhotoBindingOneOf other) {
    _$v = other as _$PhotoBindingOneOf;
  }

  @override
  void update(void Function(PhotoBindingOneOfBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhotoBindingOneOf build() => _build();

  _$PhotoBindingOneOf _build() {
    _$PhotoBindingOneOf _$result;
    try {
      _$result = _$v ??
          _$PhotoBindingOneOf._(
            piece: piece.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'piece';
        piece.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'PhotoBindingOneOf', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
