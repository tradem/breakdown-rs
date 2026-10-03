// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_scene_costume_beat_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateSceneCostumeBeatRequest extends UpdateSceneCostumeBeatRequest {
  @override
  final String costumeId;
  @override
  final String? note;
  @override
  final int version;

  factory _$UpdateSceneCostumeBeatRequest(
          [void Function(UpdateSceneCostumeBeatRequestBuilder)? updates]) =>
      (UpdateSceneCostumeBeatRequestBuilder()..update(updates))._build();

  _$UpdateSceneCostumeBeatRequest._(
      {required this.costumeId, this.note, required this.version})
      : super._();
  @override
  UpdateSceneCostumeBeatRequest rebuild(
          void Function(UpdateSceneCostumeBeatRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateSceneCostumeBeatRequestBuilder toBuilder() =>
      UpdateSceneCostumeBeatRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateSceneCostumeBeatRequest &&
        costumeId == other.costumeId &&
        note == other.note &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, costumeId.hashCode);
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateSceneCostumeBeatRequest')
          ..add('costumeId', costumeId)
          ..add('note', note)
          ..add('version', version))
        .toString();
  }
}

class UpdateSceneCostumeBeatRequestBuilder
    implements
        Builder<UpdateSceneCostumeBeatRequest,
            UpdateSceneCostumeBeatRequestBuilder> {
  _$UpdateSceneCostumeBeatRequest? _$v;

  String? _costumeId;
  String? get costumeId => _$this._costumeId;
  set costumeId(String? costumeId) => _$this._costumeId = costumeId;

  String? _note;
  String? get note => _$this._note;
  set note(String? note) => _$this._note = note;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdateSceneCostumeBeatRequestBuilder() {
    UpdateSceneCostumeBeatRequest._defaults(this);
  }

  UpdateSceneCostumeBeatRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _costumeId = $v.costumeId;
      _note = $v.note;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateSceneCostumeBeatRequest other) {
    _$v = other as _$UpdateSceneCostumeBeatRequest;
  }

  @override
  void update(void Function(UpdateSceneCostumeBeatRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateSceneCostumeBeatRequest build() => _build();

  _$UpdateSceneCostumeBeatRequest _build() {
    final _$result = _$v ??
        _$UpdateSceneCostumeBeatRequest._(
          costumeId: BuiltValueNullFieldError.checkNotNull(
              costumeId, r'UpdateSceneCostumeBeatRequest', 'costumeId'),
          note: note,
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'UpdateSceneCostumeBeatRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
