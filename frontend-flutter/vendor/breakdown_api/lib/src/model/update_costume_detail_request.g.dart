// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_costume_detail_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateCostumeDetailRequest extends UpdateCostumeDetailRequest {
  @override
  final CostumeDetailRequest detail;
  @override
  final int version;

  factory _$UpdateCostumeDetailRequest(
          [void Function(UpdateCostumeDetailRequestBuilder)? updates]) =>
      (UpdateCostumeDetailRequestBuilder()..update(updates))._build();

  _$UpdateCostumeDetailRequest._({required this.detail, required this.version})
      : super._();
  @override
  UpdateCostumeDetailRequest rebuild(
          void Function(UpdateCostumeDetailRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateCostumeDetailRequestBuilder toBuilder() =>
      UpdateCostumeDetailRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateCostumeDetailRequest &&
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
    return (newBuiltValueToStringHelper(r'UpdateCostumeDetailRequest')
          ..add('detail', detail)
          ..add('version', version))
        .toString();
  }
}

class UpdateCostumeDetailRequestBuilder
    implements
        Builder<UpdateCostumeDetailRequest, UpdateCostumeDetailRequestBuilder> {
  _$UpdateCostumeDetailRequest? _$v;

  CostumeDetailRequestBuilder? _detail;
  CostumeDetailRequestBuilder get detail =>
      _$this._detail ??= CostumeDetailRequestBuilder();
  set detail(CostumeDetailRequestBuilder? detail) => _$this._detail = detail;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdateCostumeDetailRequestBuilder() {
    UpdateCostumeDetailRequest._defaults(this);
  }

  UpdateCostumeDetailRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _detail = $v.detail.toBuilder();
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateCostumeDetailRequest other) {
    _$v = other as _$UpdateCostumeDetailRequest;
  }

  @override
  void update(void Function(UpdateCostumeDetailRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateCostumeDetailRequest build() => _build();

  _$UpdateCostumeDetailRequest _build() {
    _$UpdateCostumeDetailRequest _$result;
    try {
      _$result = _$v ??
          _$UpdateCostumeDetailRequest._(
            detail: detail.build(),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'UpdateCostumeDetailRequest', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'detail';
        detail.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'UpdateCostumeDetailRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
