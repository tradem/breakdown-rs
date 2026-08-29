// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_costume_detail_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AddCostumeDetailRequest extends AddCostumeDetailRequest {
  @override
  final CostumeDetail detail;
  @override
  final int version;

  factory _$AddCostumeDetailRequest(
          [void Function(AddCostumeDetailRequestBuilder)? updates]) =>
      (AddCostumeDetailRequestBuilder()..update(updates))._build();

  _$AddCostumeDetailRequest._({required this.detail, required this.version})
      : super._();
  @override
  AddCostumeDetailRequest rebuild(
          void Function(AddCostumeDetailRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AddCostumeDetailRequestBuilder toBuilder() =>
      AddCostumeDetailRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AddCostumeDetailRequest &&
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
    return (newBuiltValueToStringHelper(r'AddCostumeDetailRequest')
          ..add('detail', detail)
          ..add('version', version))
        .toString();
  }
}

class AddCostumeDetailRequestBuilder
    implements
        Builder<AddCostumeDetailRequest, AddCostumeDetailRequestBuilder> {
  _$AddCostumeDetailRequest? _$v;

  CostumeDetailBuilder? _detail;
  CostumeDetailBuilder get detail => _$this._detail ??= CostumeDetailBuilder();
  set detail(CostumeDetailBuilder? detail) => _$this._detail = detail;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  AddCostumeDetailRequestBuilder() {
    AddCostumeDetailRequest._defaults(this);
  }

  AddCostumeDetailRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _detail = $v.detail.toBuilder();
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AddCostumeDetailRequest other) {
    _$v = other as _$AddCostumeDetailRequest;
  }

  @override
  void update(void Function(AddCostumeDetailRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AddCostumeDetailRequest build() => _build();

  _$AddCostumeDetailRequest _build() {
    _$AddCostumeDetailRequest _$result;
    try {
      _$result = _$v ??
          _$AddCostumeDetailRequest._(
            detail: detail.build(),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'AddCostumeDetailRequest', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'detail';
        detail.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AddCostumeDetailRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
