// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_outfit_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateOutfitRequest extends CreateOutfitRequest {
  @override
  final String characterId;
  @override
  final String name;
  @override
  final BuiltList<String>? pieceIds;

  factory _$CreateOutfitRequest(
          [void Function(CreateOutfitRequestBuilder)? updates]) =>
      (CreateOutfitRequestBuilder()..update(updates))._build();

  _$CreateOutfitRequest._(
      {required this.characterId, required this.name, this.pieceIds})
      : super._();
  @override
  CreateOutfitRequest rebuild(
          void Function(CreateOutfitRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateOutfitRequestBuilder toBuilder() =>
      CreateOutfitRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateOutfitRequest &&
        characterId == other.characterId &&
        name == other.name &&
        pieceIds == other.pieceIds;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characterId.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, pieceIds.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateOutfitRequest')
          ..add('characterId', characterId)
          ..add('name', name)
          ..add('pieceIds', pieceIds))
        .toString();
  }
}

class CreateOutfitRequestBuilder
    implements Builder<CreateOutfitRequest, CreateOutfitRequestBuilder> {
  _$CreateOutfitRequest? _$v;

  String? _characterId;
  String? get characterId => _$this._characterId;
  set characterId(String? characterId) => _$this._characterId = characterId;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  ListBuilder<String>? _pieceIds;
  ListBuilder<String> get pieceIds =>
      _$this._pieceIds ??= ListBuilder<String>();
  set pieceIds(ListBuilder<String>? pieceIds) => _$this._pieceIds = pieceIds;

  CreateOutfitRequestBuilder() {
    CreateOutfitRequest._defaults(this);
  }

  CreateOutfitRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characterId = $v.characterId;
      _name = $v.name;
      _pieceIds = $v.pieceIds?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateOutfitRequest other) {
    _$v = other as _$CreateOutfitRequest;
  }

  @override
  void update(void Function(CreateOutfitRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateOutfitRequest build() => _build();

  _$CreateOutfitRequest _build() {
    _$CreateOutfitRequest _$result;
    try {
      _$result = _$v ??
          _$CreateOutfitRequest._(
            characterId: BuiltValueNullFieldError.checkNotNull(
                characterId, r'CreateOutfitRequest', 'characterId'),
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'CreateOutfitRequest', 'name'),
            pieceIds: _pieceIds?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'pieceIds';
        _pieceIds?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'CreateOutfitRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
