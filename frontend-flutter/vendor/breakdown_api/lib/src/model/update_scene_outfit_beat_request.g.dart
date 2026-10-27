// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_scene_outfit_beat_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateSceneOutfitBeatRequest extends UpdateSceneOutfitBeatRequest {
  @override
  final String? note;
  @override
  final String outfitId;
  @override
  final int version;

  factory _$UpdateSceneOutfitBeatRequest(
          [void Function(UpdateSceneOutfitBeatRequestBuilder)? updates]) =>
      (UpdateSceneOutfitBeatRequestBuilder()..update(updates))._build();

  _$UpdateSceneOutfitBeatRequest._(
      {this.note, required this.outfitId, required this.version})
      : super._();
  @override
  UpdateSceneOutfitBeatRequest rebuild(
          void Function(UpdateSceneOutfitBeatRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateSceneOutfitBeatRequestBuilder toBuilder() =>
      UpdateSceneOutfitBeatRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateSceneOutfitBeatRequest &&
        note == other.note &&
        outfitId == other.outfitId &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jc(_$hash, outfitId.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateSceneOutfitBeatRequest')
          ..add('note', note)
          ..add('outfitId', outfitId)
          ..add('version', version))
        .toString();
  }
}

class UpdateSceneOutfitBeatRequestBuilder
    implements
        Builder<UpdateSceneOutfitBeatRequest,
            UpdateSceneOutfitBeatRequestBuilder> {
  _$UpdateSceneOutfitBeatRequest? _$v;

  String? _note;
  String? get note => _$this._note;
  set note(String? note) => _$this._note = note;

  String? _outfitId;
  String? get outfitId => _$this._outfitId;
  set outfitId(String? outfitId) => _$this._outfitId = outfitId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdateSceneOutfitBeatRequestBuilder() {
    UpdateSceneOutfitBeatRequest._defaults(this);
  }

  UpdateSceneOutfitBeatRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _note = $v.note;
      _outfitId = $v.outfitId;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateSceneOutfitBeatRequest other) {
    _$v = other as _$UpdateSceneOutfitBeatRequest;
  }

  @override
  void update(void Function(UpdateSceneOutfitBeatRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateSceneOutfitBeatRequest build() => _build();

  _$UpdateSceneOutfitBeatRequest _build() {
    final _$result = _$v ??
        _$UpdateSceneOutfitBeatRequest._(
          note: note,
          outfitId: BuiltValueNullFieldError.checkNotNull(
              outfitId, r'UpdateSceneOutfitBeatRequest', 'outfitId'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'UpdateSceneOutfitBeatRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
