// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_note_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateNoteRequest extends UpdateNoteRequest {
  @override
  final String body;
  @override
  final int version;

  factory _$UpdateNoteRequest(
          [void Function(UpdateNoteRequestBuilder)? updates]) =>
      (UpdateNoteRequestBuilder()..update(updates))._build();

  _$UpdateNoteRequest._({required this.body, required this.version})
      : super._();
  @override
  UpdateNoteRequest rebuild(void Function(UpdateNoteRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateNoteRequestBuilder toBuilder() =>
      UpdateNoteRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateNoteRequest &&
        body == other.body &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, body.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateNoteRequest')
          ..add('body', body)
          ..add('version', version))
        .toString();
  }
}

class UpdateNoteRequestBuilder
    implements Builder<UpdateNoteRequest, UpdateNoteRequestBuilder> {
  _$UpdateNoteRequest? _$v;

  String? _body;
  String? get body => _$this._body;
  set body(String? body) => _$this._body = body;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdateNoteRequestBuilder() {
    UpdateNoteRequest._defaults(this);
  }

  UpdateNoteRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _body = $v.body;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateNoteRequest other) {
    _$v = other as _$UpdateNoteRequest;
  }

  @override
  void update(void Function(UpdateNoteRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateNoteRequest build() => _build();

  _$UpdateNoteRequest _build() {
    final _$result = _$v ??
        _$UpdateNoteRequest._(
          body: BuiltValueNullFieldError.checkNotNull(
              body, r'UpdateNoteRequest', 'body'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'UpdateNoteRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
