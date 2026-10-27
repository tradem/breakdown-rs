// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rename_outfit_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RenameOutfitRequest extends RenameOutfitRequest {
  @override
  final String name;
  @override
  final int version;

  factory _$RenameOutfitRequest(
          [void Function(RenameOutfitRequestBuilder)? updates]) =>
      (RenameOutfitRequestBuilder()..update(updates))._build();

  _$RenameOutfitRequest._({required this.name, required this.version})
      : super._();
  @override
  RenameOutfitRequest rebuild(
          void Function(RenameOutfitRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RenameOutfitRequestBuilder toBuilder() =>
      RenameOutfitRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RenameOutfitRequest &&
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
    return (newBuiltValueToStringHelper(r'RenameOutfitRequest')
          ..add('name', name)
          ..add('version', version))
        .toString();
  }
}

class RenameOutfitRequestBuilder
    implements Builder<RenameOutfitRequest, RenameOutfitRequestBuilder> {
  _$RenameOutfitRequest? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  RenameOutfitRequestBuilder() {
    RenameOutfitRequest._defaults(this);
  }

  RenameOutfitRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RenameOutfitRequest other) {
    _$v = other as _$RenameOutfitRequest;
  }

  @override
  void update(void Function(RenameOutfitRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RenameOutfitRequest build() => _build();

  _$RenameOutfitRequest _build() {
    final _$result = _$v ??
        _$RenameOutfitRequest._(
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'RenameOutfitRequest', 'name'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'RenameOutfitRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
