// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_note_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AddNoteRequest extends AddNoteRequest {
  @override
  final String body;
  @override
  final String? noteId;

  factory _$AddNoteRequest([void Function(AddNoteRequestBuilder)? updates]) =>
      (AddNoteRequestBuilder()..update(updates))._build();

  _$AddNoteRequest._({required this.body, this.noteId}) : super._();
  @override
  AddNoteRequest rebuild(void Function(AddNoteRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AddNoteRequestBuilder toBuilder() => AddNoteRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AddNoteRequest &&
        body == other.body &&
        noteId == other.noteId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, body.hashCode);
    _$hash = $jc(_$hash, noteId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AddNoteRequest')
          ..add('body', body)
          ..add('noteId', noteId))
        .toString();
  }
}

class AddNoteRequestBuilder
    implements Builder<AddNoteRequest, AddNoteRequestBuilder> {
  _$AddNoteRequest? _$v;

  String? _body;
  String? get body => _$this._body;
  set body(String? body) => _$this._body = body;

  String? _noteId;
  String? get noteId => _$this._noteId;
  set noteId(String? noteId) => _$this._noteId = noteId;

  AddNoteRequestBuilder() {
    AddNoteRequest._defaults(this);
  }

  AddNoteRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _body = $v.body;
      _noteId = $v.noteId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AddNoteRequest other) {
    _$v = other as _$AddNoteRequest;
  }

  @override
  void update(void Function(AddNoteRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AddNoteRequest build() => _build();

  _$AddNoteRequest _build() {
    final _$result = _$v ??
        _$AddNoteRequest._(
          body: BuiltValueNullFieldError.checkNotNull(
              body, r'AddNoteRequest', 'body'),
          noteId: noteId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
