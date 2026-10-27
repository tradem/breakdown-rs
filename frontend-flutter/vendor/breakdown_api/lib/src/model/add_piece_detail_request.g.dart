// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_piece_detail_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AddPieceDetailRequest extends AddPieceDetailRequest {
  @override
  final PieceDetailRequest detail;
  @override
  final int version;

  factory _$AddPieceDetailRequest(
          [void Function(AddPieceDetailRequestBuilder)? updates]) =>
      (AddPieceDetailRequestBuilder()..update(updates))._build();

  _$AddPieceDetailRequest._({required this.detail, required this.version})
      : super._();
  @override
  AddPieceDetailRequest rebuild(
          void Function(AddPieceDetailRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AddPieceDetailRequestBuilder toBuilder() =>
      AddPieceDetailRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AddPieceDetailRequest &&
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
    return (newBuiltValueToStringHelper(r'AddPieceDetailRequest')
          ..add('detail', detail)
          ..add('version', version))
        .toString();
  }
}

class AddPieceDetailRequestBuilder
    implements Builder<AddPieceDetailRequest, AddPieceDetailRequestBuilder> {
  _$AddPieceDetailRequest? _$v;

  PieceDetailRequestBuilder? _detail;
  PieceDetailRequestBuilder get detail =>
      _$this._detail ??= PieceDetailRequestBuilder();
  set detail(PieceDetailRequestBuilder? detail) => _$this._detail = detail;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  AddPieceDetailRequestBuilder() {
    AddPieceDetailRequest._defaults(this);
  }

  AddPieceDetailRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _detail = $v.detail.toBuilder();
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AddPieceDetailRequest other) {
    _$v = other as _$AddPieceDetailRequest;
  }

  @override
  void update(void Function(AddPieceDetailRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AddPieceDetailRequest build() => _build();

  _$AddPieceDetailRequest _build() {
    _$AddPieceDetailRequest _$result;
    try {
      _$result = _$v ??
          _$AddPieceDetailRequest._(
            detail: detail.build(),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'AddPieceDetailRequest', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'detail';
        detail.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AddPieceDetailRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
