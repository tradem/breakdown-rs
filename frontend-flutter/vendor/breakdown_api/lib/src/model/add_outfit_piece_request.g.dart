// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_outfit_piece_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AddOutfitPieceRequest extends AddOutfitPieceRequest {
  @override
  final String pieceId;
  @override
  final int version;

  factory _$AddOutfitPieceRequest(
          [void Function(AddOutfitPieceRequestBuilder)? updates]) =>
      (AddOutfitPieceRequestBuilder()..update(updates))._build();

  _$AddOutfitPieceRequest._({required this.pieceId, required this.version})
      : super._();
  @override
  AddOutfitPieceRequest rebuild(
          void Function(AddOutfitPieceRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AddOutfitPieceRequestBuilder toBuilder() =>
      AddOutfitPieceRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AddOutfitPieceRequest &&
        pieceId == other.pieceId &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pieceId.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AddOutfitPieceRequest')
          ..add('pieceId', pieceId)
          ..add('version', version))
        .toString();
  }
}

class AddOutfitPieceRequestBuilder
    implements Builder<AddOutfitPieceRequest, AddOutfitPieceRequestBuilder> {
  _$AddOutfitPieceRequest? _$v;

  String? _pieceId;
  String? get pieceId => _$this._pieceId;
  set pieceId(String? pieceId) => _$this._pieceId = pieceId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  AddOutfitPieceRequestBuilder() {
    AddOutfitPieceRequest._defaults(this);
  }

  AddOutfitPieceRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pieceId = $v.pieceId;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AddOutfitPieceRequest other) {
    _$v = other as _$AddOutfitPieceRequest;
  }

  @override
  void update(void Function(AddOutfitPieceRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AddOutfitPieceRequest build() => _build();

  _$AddOutfitPieceRequest _build() {
    final _$result = _$v ??
        _$AddOutfitPieceRequest._(
          pieceId: BuiltValueNullFieldError.checkNotNull(
              pieceId, r'AddOutfitPieceRequest', 'pieceId'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'AddOutfitPieceRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
