// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_piece_notes_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdatePieceNotesRequest extends UpdatePieceNotesRequest {
  @override
  final String notes;
  @override
  final int version;

  factory _$UpdatePieceNotesRequest(
          [void Function(UpdatePieceNotesRequestBuilder)? updates]) =>
      (UpdatePieceNotesRequestBuilder()..update(updates))._build();

  _$UpdatePieceNotesRequest._({required this.notes, required this.version})
      : super._();
  @override
  UpdatePieceNotesRequest rebuild(
          void Function(UpdatePieceNotesRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdatePieceNotesRequestBuilder toBuilder() =>
      UpdatePieceNotesRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdatePieceNotesRequest &&
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
    return (newBuiltValueToStringHelper(r'UpdatePieceNotesRequest')
          ..add('notes', notes)
          ..add('version', version))
        .toString();
  }
}

class UpdatePieceNotesRequestBuilder
    implements
        Builder<UpdatePieceNotesRequest, UpdatePieceNotesRequestBuilder> {
  _$UpdatePieceNotesRequest? _$v;

  String? _notes;
  String? get notes => _$this._notes;
  set notes(String? notes) => _$this._notes = notes;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdatePieceNotesRequestBuilder() {
    UpdatePieceNotesRequest._defaults(this);
  }

  UpdatePieceNotesRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _notes = $v.notes;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdatePieceNotesRequest other) {
    _$v = other as _$UpdatePieceNotesRequest;
  }

  @override
  void update(void Function(UpdatePieceNotesRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdatePieceNotesRequest build() => _build();

  _$UpdatePieceNotesRequest _build() {
    final _$result = _$v ??
        _$UpdatePieceNotesRequest._(
          notes: BuiltValueNullFieldError.checkNotNull(
              notes, r'UpdatePieceNotesRequest', 'notes'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'UpdatePieceNotesRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
