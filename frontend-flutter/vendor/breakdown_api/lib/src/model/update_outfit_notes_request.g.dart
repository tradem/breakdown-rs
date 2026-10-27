// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_outfit_notes_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateOutfitNotesRequest extends UpdateOutfitNotesRequest {
  @override
  final String notes;
  @override
  final int version;

  factory _$UpdateOutfitNotesRequest(
          [void Function(UpdateOutfitNotesRequestBuilder)? updates]) =>
      (UpdateOutfitNotesRequestBuilder()..update(updates))._build();

  _$UpdateOutfitNotesRequest._({required this.notes, required this.version})
      : super._();
  @override
  UpdateOutfitNotesRequest rebuild(
          void Function(UpdateOutfitNotesRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateOutfitNotesRequestBuilder toBuilder() =>
      UpdateOutfitNotesRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateOutfitNotesRequest &&
        notes == other.notes &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateOutfitNotesRequest')
          ..add('notes', notes)
          ..add('version', version))
        .toString();
  }
}

class UpdateOutfitNotesRequestBuilder
    implements
        Builder<UpdateOutfitNotesRequest, UpdateOutfitNotesRequestBuilder> {
  _$UpdateOutfitNotesRequest? _$v;

  String? _notes;
  String? get notes => _$this._notes;
  set notes(String? notes) => _$this._notes = notes;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdateOutfitNotesRequestBuilder() {
    UpdateOutfitNotesRequest._defaults(this);
  }

  UpdateOutfitNotesRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _notes = $v.notes;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateOutfitNotesRequest other) {
    _$v = other as _$UpdateOutfitNotesRequest;
  }

  @override
  void update(void Function(UpdateOutfitNotesRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateOutfitNotesRequest build() => _build();

  _$UpdateOutfitNotesRequest _build() {
    final _$result = _$v ??
        _$UpdateOutfitNotesRequest._(
          notes: BuiltValueNullFieldError.checkNotNull(
              notes, r'UpdateOutfitNotesRequest', 'notes'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'UpdateOutfitNotesRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
