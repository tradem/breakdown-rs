// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rename_episode_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RenameEpisodeRequest extends RenameEpisodeRequest {
  @override
  final String? name;
  @override
  final int version;

  factory _$RenameEpisodeRequest(
          [void Function(RenameEpisodeRequestBuilder)? updates]) =>
      (RenameEpisodeRequestBuilder()..update(updates))._build();

  _$RenameEpisodeRequest._({this.name, required this.version}) : super._();
  @override
  RenameEpisodeRequest rebuild(
          void Function(RenameEpisodeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RenameEpisodeRequestBuilder toBuilder() =>
      RenameEpisodeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RenameEpisodeRequest &&
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
    return (newBuiltValueToStringHelper(r'RenameEpisodeRequest')
          ..add('name', name)
          ..add('version', version))
        .toString();
  }
}

class RenameEpisodeRequestBuilder
    implements Builder<RenameEpisodeRequest, RenameEpisodeRequestBuilder> {
  _$RenameEpisodeRequest? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  RenameEpisodeRequestBuilder() {
    RenameEpisodeRequest._defaults(this);
  }

  RenameEpisodeRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RenameEpisodeRequest other) {
    _$v = other as _$RenameEpisodeRequest;
  }

  @override
  void update(void Function(RenameEpisodeRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RenameEpisodeRequest build() => _build();

  _$RenameEpisodeRequest _build() {
    final _$result = _$v ??
        _$RenameEpisodeRequest._(
          name: name,
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'RenameEpisodeRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
