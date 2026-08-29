// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'id_version_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$IdVersionResponse extends IdVersionResponse {
  @override
  final String id;
  @override
  final int version;

  factory _$IdVersionResponse(
          [void Function(IdVersionResponseBuilder)? updates]) =>
      (IdVersionResponseBuilder()..update(updates))._build();

  _$IdVersionResponse._({required this.id, required this.version}) : super._();
  @override
  IdVersionResponse rebuild(void Function(IdVersionResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  IdVersionResponseBuilder toBuilder() =>
      IdVersionResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is IdVersionResponse &&
        id == other.id &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'IdVersionResponse')
          ..add('id', id)
          ..add('version', version))
        .toString();
  }
}

class IdVersionResponseBuilder
    implements Builder<IdVersionResponse, IdVersionResponseBuilder> {
  _$IdVersionResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  IdVersionResponseBuilder() {
    IdVersionResponse._defaults(this);
  }

  IdVersionResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(IdVersionResponse other) {
    _$v = other as _$IdVersionResponse;
  }

  @override
  void update(void Function(IdVersionResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  IdVersionResponse build() => _build();

  _$IdVersionResponse _build() {
    final _$result = _$v ??
        _$IdVersionResponse._(
          id: BuiltValueNullFieldError.checkNotNull(
              id, r'IdVersionResponse', 'id'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'IdVersionResponse', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
