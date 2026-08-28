// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_costume_notes_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateCostumeNotesRequest extends UpdateCostumeNotesRequest {
  @override
  final String notes;
  @override
  final int version;

  factory _$UpdateCostumeNotesRequest(
          [void Function(UpdateCostumeNotesRequestBuilder)? updates]) =>
      (UpdateCostumeNotesRequestBuilder()..update(updates))._build();

  _$UpdateCostumeNotesRequest._({required this.notes, required this.version})
      : super._();
  @override
  UpdateCostumeNotesRequest rebuild(
          void Function(UpdateCostumeNotesRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateCostumeNotesRequestBuilder toBuilder() =>
      UpdateCostumeNotesRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateCostumeNotesRequest &&
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
    return (newBuiltValueToStringHelper(r'UpdateCostumeNotesRequest')
          ..add('notes', notes)
          ..add('version', version))
        .toString();
  }
}

class UpdateCostumeNotesRequestBuilder
    implements
        Builder<UpdateCostumeNotesRequest, UpdateCostumeNotesRequestBuilder> {
  _$UpdateCostumeNotesRequest? _$v;

  String? _notes;
  String? get notes => _$this._notes;
  set notes(String? notes) => _$this._notes = notes;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdateCostumeNotesRequestBuilder() {
    UpdateCostumeNotesRequest._defaults(this);
  }

  UpdateCostumeNotesRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _notes = $v.notes;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateCostumeNotesRequest other) {
    _$v = other as _$UpdateCostumeNotesRequest;
  }

  @override
  void update(void Function(UpdateCostumeNotesRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateCostumeNotesRequest build() => _build();

  _$UpdateCostumeNotesRequest _build() {
    final _$result = _$v ??
        _$UpdateCostumeNotesRequest._(
          notes: BuiltValueNullFieldError.checkNotNull(
              notes, r'UpdateCostumeNotesRequest', 'notes'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'UpdateCostumeNotesRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
