// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_variant.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const PhotoVariant _$original = const PhotoVariant._('original');
const PhotoVariant _$thumb = const PhotoVariant._('thumb');
const PhotoVariant _$medium = const PhotoVariant._('medium');

PhotoVariant _$valueOf(String name) {
  switch (name) {
    case 'original':
      return _$original;
    case 'thumb':
      return _$thumb;
    case 'medium':
      return _$medium;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PhotoVariant> _$values =
    BuiltSet<PhotoVariant>(const <PhotoVariant>[
  _$original,
  _$thumb,
  _$medium,
]);

class _$PhotoVariantMeta {
  const _$PhotoVariantMeta();
  PhotoVariant get original => _$original;
  PhotoVariant get thumb => _$thumb;
  PhotoVariant get medium => _$medium;
  PhotoVariant valueOf(String name) => _$valueOf(name);
  BuiltSet<PhotoVariant> get values => _$values;
}

abstract class _$PhotoVariantMixin {
  // ignore: non_constant_identifier_names
  _$PhotoVariantMeta get PhotoVariant => const _$PhotoVariantMeta();
}

Serializer<PhotoVariant> _$photoVariantSerializer = _$PhotoVariantSerializer();

class _$PhotoVariantSerializer implements PrimitiveSerializer<PhotoVariant> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'original': 'Original',
    'thumb': 'Thumb',
    'medium': 'Medium',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'Original': 'original',
    'Thumb': 'thumb',
    'Medium': 'medium',
  };

  @override
  final Iterable<Type> types = const <Type>[PhotoVariant];
  @override
  final String wireName = 'PhotoVariant';

  @override
  Object serialize(Serializers serializers, PhotoVariant object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  PhotoVariant deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      PhotoVariant.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
