// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_character.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DraftCharacter extends DraftCharacter {
  @override
  final CharacterCategory? category;
  @override
  final String name;

  factory _$DraftCharacter([void Function(DraftCharacterBuilder)? updates]) =>
      (DraftCharacterBuilder()..update(updates))._build();

  _$DraftCharacter._({this.category, required this.name}) : super._();
  @override
  DraftCharacter rebuild(void Function(DraftCharacterBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DraftCharacterBuilder toBuilder() => DraftCharacterBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DraftCharacter &&
        category == other.category &&
        name == other.name;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DraftCharacter')
          ..add('category', category)
          ..add('name', name))
        .toString();
  }
}

class DraftCharacterBuilder
    implements Builder<DraftCharacter, DraftCharacterBuilder> {
  _$DraftCharacter? _$v;

  CharacterCategory? _category;
  CharacterCategory? get category => _$this._category;
  set category(CharacterCategory? category) => _$this._category = category;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  DraftCharacterBuilder() {
    DraftCharacter._defaults(this);
  }

  DraftCharacterBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _category = $v.category;
      _name = $v.name;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DraftCharacter other) {
    _$v = other as _$DraftCharacter;
  }

  @override
  void update(void Function(DraftCharacterBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DraftCharacter build() => _build();

  _$DraftCharacter _build() {
    final _$result = _$v ??
        _$DraftCharacter._(
          category: category,
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'DraftCharacter', 'name'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
