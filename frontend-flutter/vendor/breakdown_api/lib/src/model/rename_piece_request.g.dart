// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rename_piece_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RenamePieceRequest extends RenamePieceRequest {
  @override
  final String name;
  @override
  final int version;

  factory _$RenamePieceRequest(
          [void Function(RenamePieceRequestBuilder)? updates]) =>
      (RenamePieceRequestBuilder()..update(updates))._build();

  _$RenamePieceRequest._({required this.name, required this.version})
      : super._();
  @override
  RenamePieceRequest rebuild(
          void Function(RenamePieceRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RenamePieceRequestBuilder toBuilder() =>
      RenamePieceRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RenamePieceRequest &&
        name == other.name &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RenamePieceRequest')
          ..add('name', name)
          ..add('version', version))
        .toString();
  }
}

class RenamePieceRequestBuilder
    implements Builder<RenamePieceRequest, RenamePieceRequestBuilder> {
  _$RenamePieceRequest? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  RenamePieceRequestBuilder() {
    RenamePieceRequest._defaults(this);
  }

  RenamePieceRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RenamePieceRequest other) {
    _$v = other as _$RenamePieceRequest;
  }

  @override
  void update(void Function(RenamePieceRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RenamePieceRequest build() => _build();

  _$RenamePieceRequest _build() {
    final _$result = _$v ??
        _$RenamePieceRequest._(
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'RenamePieceRequest', 'name'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'RenamePieceRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
