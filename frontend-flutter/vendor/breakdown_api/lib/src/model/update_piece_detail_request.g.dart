// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_piece_detail_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdatePieceDetailRequest extends UpdatePieceDetailRequest {
  @override
  final PieceDetailRequest detail;
  @override
  final int version;

  factory _$UpdatePieceDetailRequest(
          [void Function(UpdatePieceDetailRequestBuilder)? updates]) =>
      (UpdatePieceDetailRequestBuilder()..update(updates))._build();

  _$UpdatePieceDetailRequest._({required this.detail, required this.version})
      : super._();
  @override
  UpdatePieceDetailRequest rebuild(
          void Function(UpdatePieceDetailRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdatePieceDetailRequestBuilder toBuilder() =>
      UpdatePieceDetailRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdatePieceDetailRequest &&
        detail == other.detail &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, detail.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdatePieceDetailRequest')
          ..add('detail', detail)
          ..add('version', version))
        .toString();
  }
}

class UpdatePieceDetailRequestBuilder
    implements
        Builder<UpdatePieceDetailRequest, UpdatePieceDetailRequestBuilder> {
  _$UpdatePieceDetailRequest? _$v;

  PieceDetailRequestBuilder? _detail;
  PieceDetailRequestBuilder get detail =>
      _$this._detail ??= PieceDetailRequestBuilder();
  set detail(PieceDetailRequestBuilder? detail) => _$this._detail = detail;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdatePieceDetailRequestBuilder() {
    UpdatePieceDetailRequest._defaults(this);
  }

  UpdatePieceDetailRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _detail = $v.detail.toBuilder();
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdatePieceDetailRequest other) {
    _$v = other as _$UpdatePieceDetailRequest;
  }

  @override
  void update(void Function(UpdatePieceDetailRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdatePieceDetailRequest build() => _build();

  _$UpdatePieceDetailRequest _build() {
    _$UpdatePieceDetailRequest _$result;
    try {
      _$result = _$v ??
          _$UpdatePieceDetailRequest._(
            detail: detail.build(),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'UpdatePieceDetailRequest', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'detail';
        detail.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'UpdatePieceDetailRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
