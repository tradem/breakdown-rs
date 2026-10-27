// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_outfit_variant_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateOutfitVariantRequest extends CreateOutfitVariantRequest {
  @override
  final String? name;
  @override
  final String? notes;
  @override
  final BuiltList<String>? pieceIds;

  factory _$CreateOutfitVariantRequest(
          [void Function(CreateOutfitVariantRequestBuilder)? updates]) =>
      (CreateOutfitVariantRequestBuilder()..update(updates))._build();

  _$CreateOutfitVariantRequest._({this.name, this.notes, this.pieceIds})
      : super._();
  @override
  CreateOutfitVariantRequest rebuild(
          void Function(CreateOutfitVariantRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateOutfitVariantRequestBuilder toBuilder() =>
      CreateOutfitVariantRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateOutfitVariantRequest &&
        name == other.name &&
        notes == other.notes &&
        pieceIds == other.pieceIds;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, pieceIds.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateOutfitVariantRequest')
          ..add('name', name)
          ..add('notes', notes)
          ..add('pieceIds', pieceIds))
        .toString();
  }
}

class CreateOutfitVariantRequestBuilder
    implements
        Builder<CreateOutfitVariantRequest, CreateOutfitVariantRequestBuilder> {
  _$CreateOutfitVariantRequest? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _notes;
  String? get notes => _$this._notes;
  set notes(String? notes) => _$this._notes = notes;

  ListBuilder<String>? _pieceIds;
  ListBuilder<String> get pieceIds =>
      _$this._pieceIds ??= ListBuilder<String>();
  set pieceIds(ListBuilder<String>? pieceIds) => _$this._pieceIds = pieceIds;

  CreateOutfitVariantRequestBuilder() {
    CreateOutfitVariantRequest._defaults(this);
  }

  CreateOutfitVariantRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _notes = $v.notes;
      _pieceIds = $v.pieceIds?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateOutfitVariantRequest other) {
    _$v = other as _$CreateOutfitVariantRequest;
  }

  @override
  void update(void Function(CreateOutfitVariantRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateOutfitVariantRequest build() => _build();

  _$CreateOutfitVariantRequest _build() {
    _$CreateOutfitVariantRequest _$result;
    try {
      _$result = _$v ??
          _$CreateOutfitVariantRequest._(
            name: name,
            notes: notes,
            pieceIds: _pieceIds?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'pieceIds';
        _pieceIds?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'CreateOutfitVariantRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
