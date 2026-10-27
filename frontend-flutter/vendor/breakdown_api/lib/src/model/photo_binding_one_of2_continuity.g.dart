// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_binding_one_of2_continuity.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhotoBindingOneOf2Continuity extends PhotoBindingOneOf2Continuity {
  @override
  final String? pieceId;
  @override
  final String sceneShootId;

  factory _$PhotoBindingOneOf2Continuity(
          [void Function(PhotoBindingOneOf2ContinuityBuilder)? updates]) =>
      (PhotoBindingOneOf2ContinuityBuilder()..update(updates))._build();

  _$PhotoBindingOneOf2Continuity._({this.pieceId, required this.sceneShootId})
      : super._();
  @override
  PhotoBindingOneOf2Continuity rebuild(
          void Function(PhotoBindingOneOf2ContinuityBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhotoBindingOneOf2ContinuityBuilder toBuilder() =>
      PhotoBindingOneOf2ContinuityBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhotoBindingOneOf2Continuity &&
        pieceId == other.pieceId &&
        sceneShootId == other.sceneShootId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pieceId.hashCode);
    _$hash = $jc(_$hash, sceneShootId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhotoBindingOneOf2Continuity')
          ..add('pieceId', pieceId)
          ..add('sceneShootId', sceneShootId))
        .toString();
  }
}

class PhotoBindingOneOf2ContinuityBuilder
    implements
        Builder<PhotoBindingOneOf2Continuity,
            PhotoBindingOneOf2ContinuityBuilder> {
  _$PhotoBindingOneOf2Continuity? _$v;

  String? _pieceId;
  String? get pieceId => _$this._pieceId;
  set pieceId(String? pieceId) => _$this._pieceId = pieceId;

  String? _sceneShootId;
  String? get sceneShootId => _$this._sceneShootId;
  set sceneShootId(String? sceneShootId) => _$this._sceneShootId = sceneShootId;

  PhotoBindingOneOf2ContinuityBuilder() {
    PhotoBindingOneOf2Continuity._defaults(this);
  }

  PhotoBindingOneOf2ContinuityBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pieceId = $v.pieceId;
      _sceneShootId = $v.sceneShootId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhotoBindingOneOf2Continuity other) {
    _$v = other as _$PhotoBindingOneOf2Continuity;
  }

  @override
  void update(void Function(PhotoBindingOneOf2ContinuityBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhotoBindingOneOf2Continuity build() => _build();

  _$PhotoBindingOneOf2Continuity _build() {
    final _$result = _$v ??
        _$PhotoBindingOneOf2Continuity._(
          pieceId: pieceId,
          sceneShootId: BuiltValueNullFieldError.checkNotNull(
              sceneShootId, r'PhotoBindingOneOf2Continuity', 'sceneShootId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
