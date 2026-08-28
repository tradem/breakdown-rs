// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_character_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateCharacterRequest extends CreateCharacterRequest {
  @override
  final CharacterCategory category;
  @override
  final String name;
  @override
  final String seasonId;

  factory _$CreateCharacterRequest(
          [void Function(CreateCharacterRequestBuilder)? updates]) =>
      (CreateCharacterRequestBuilder()..update(updates))._build();

  _$CreateCharacterRequest._(
      {required this.category, required this.name, required this.seasonId})
      : super._();
  @override
  CreateCharacterRequest rebuild(
          void Function(CreateCharacterRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateCharacterRequestBuilder toBuilder() =>
      CreateCharacterRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateCharacterRequest &&
        category == other.category &&
        name == other.name &&
        seasonId == other.seasonId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, seasonId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateCharacterRequest')
          ..add('category', category)
          ..add('name', name)
          ..add('seasonId', seasonId))
        .toString();
  }
}

class CreateCharacterRequestBuilder
    implements Builder<CreateCharacterRequest, CreateCharacterRequestBuilder> {
  _$CreateCharacterRequest? _$v;

  CharacterCategory? _category;
  CharacterCategory? get category => _$this._category;
  set category(CharacterCategory? category) => _$this._category = category;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _seasonId;
  String? get seasonId => _$this._seasonId;
  set seasonId(String? seasonId) => _$this._seasonId = seasonId;

  CreateCharacterRequestBuilder() {
    CreateCharacterRequest._defaults(this);
  }

  CreateCharacterRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _category = $v.category;
      _name = $v.name;
      _seasonId = $v.seasonId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateCharacterRequest other) {
    _$v = other as _$CreateCharacterRequest;
  }

  @override
  void update(void Function(CreateCharacterRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateCharacterRequest build() => _build();

  _$CreateCharacterRequest _build() {
    final _$result = _$v ??
        _$CreateCharacterRequest._(
          category: BuiltValueNullFieldError.checkNotNull(
              category, r'CreateCharacterRequest', 'category'),
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'CreateCharacterRequest', 'name'),
          seasonId: BuiltValueNullFieldError.checkNotNull(
              seasonId, r'CreateCharacterRequest', 'seasonId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
