// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rename_season_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RenameSeasonRequest extends RenameSeasonRequest {
  @override
  final String? title;
  @override
  final int version;

  factory _$RenameSeasonRequest(
          [void Function(RenameSeasonRequestBuilder)? updates]) =>
      (RenameSeasonRequestBuilder()..update(updates))._build();

  _$RenameSeasonRequest._({this.title, required this.version}) : super._();
  @override
  RenameSeasonRequest rebuild(
          void Function(RenameSeasonRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RenameSeasonRequestBuilder toBuilder() =>
      RenameSeasonRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RenameSeasonRequest &&
        title == other.title &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RenameSeasonRequest')
          ..add('title', title)
          ..add('version', version))
        .toString();
  }
}

class RenameSeasonRequestBuilder
    implements Builder<RenameSeasonRequest, RenameSeasonRequestBuilder> {
  _$RenameSeasonRequest? _$v;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  RenameSeasonRequestBuilder() {
    RenameSeasonRequest._defaults(this);
  }

  RenameSeasonRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _title = $v.title;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RenameSeasonRequest other) {
    _$v = other as _$RenameSeasonRequest;
  }

  @override
  void update(void Function(RenameSeasonRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RenameSeasonRequest build() => _build();

  _$RenameSeasonRequest _build() {
    final _$result = _$v ??
        _$RenameSeasonRequest._(
          title: title,
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'RenameSeasonRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
