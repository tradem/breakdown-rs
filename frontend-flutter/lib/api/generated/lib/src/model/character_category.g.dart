// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'character_category.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const CharacterCategory _$mainCast = const CharacterCategory._('mainCast');
const CharacterCategory _$guest = const CharacterCategory._('guest');
const CharacterCategory _$extra = const CharacterCategory._('extra');

CharacterCategory _$valueOf(String name) {
  switch (name) {
    case 'mainCast':
      return _$mainCast;
    case 'guest':
      return _$guest;
    case 'extra':
      return _$extra;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<CharacterCategory> _$values =
    BuiltSet<CharacterCategory>(const <CharacterCategory>[
  _$mainCast,
  _$guest,
  _$extra,
]);

class _$CharacterCategoryMeta {
  const _$CharacterCategoryMeta();
  CharacterCategory get mainCast => _$mainCast;
  CharacterCategory get guest => _$guest;
  CharacterCategory get extra => _$extra;
  CharacterCategory valueOf(String name) => _$valueOf(name);
  BuiltSet<CharacterCategory> get values => _$values;
}

abstract class _$CharacterCategoryMixin {
  // ignore: non_constant_identifier_names
  _$CharacterCategoryMeta get CharacterCategory =>
      const _$CharacterCategoryMeta();
}

Serializer<CharacterCategory> _$characterCategorySerializer =
    _$CharacterCategorySerializer();

class _$CharacterCategorySerializer
    implements PrimitiveSerializer<CharacterCategory> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'mainCast': 'main_cast',
    'guest': 'guest',
    'extra': 'extra',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'main_cast': 'mainCast',
    'guest': 'guest',
    'extra': 'extra',
  };

  @override
  final Iterable<Type> types = const <Type>[CharacterCategory];
  @override
  final String wireName = 'CharacterCategory';

  @override
  Object serialize(Serializers serializers, CharacterCategory object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  CharacterCategory deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      CharacterCategory.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
