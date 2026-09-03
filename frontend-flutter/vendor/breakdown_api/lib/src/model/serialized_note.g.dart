// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'serialized_note.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SerializedNote extends SerializedNote {
  @override
  final String body;
  @override
  final String id;

  factory _$SerializedNote([void Function(SerializedNoteBuilder)? updates]) =>
      (SerializedNoteBuilder()..update(updates))._build();

  _$SerializedNote._({required this.body, required this.id}) : super._();
  @override
  SerializedNote rebuild(void Function(SerializedNoteBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SerializedNoteBuilder toBuilder() => SerializedNoteBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SerializedNote && body == other.body && id == other.id;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, body.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SerializedNote')
          ..add('body', body)
          ..add('id', id))
        .toString();
  }
}

class SerializedNoteBuilder
    implements Builder<SerializedNote, SerializedNoteBuilder> {
  _$SerializedNote? _$v;

  String? _body;
  String? get body => _$this._body;
  set body(String? body) => _$this._body = body;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  SerializedNoteBuilder() {
    SerializedNote._defaults(this);
  }

  SerializedNoteBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _body = $v.body;
      _id = $v.id;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SerializedNote other) {
    _$v = other as _$SerializedNote;
  }

  @override
  void update(void Function(SerializedNoteBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SerializedNote build() => _build();

  _$SerializedNote _build() {
    final _$result = _$v ??
        _$SerializedNote._(
          body: BuiltValueNullFieldError.checkNotNull(
              body, r'SerializedNote', 'body'),
          id: BuiltValueNullFieldError.checkNotNull(
              id, r'SerializedNote', 'id'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
