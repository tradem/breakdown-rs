// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'photo_bytes_query.g.dart';

/// Query parameters for the photo bytes endpoint.
///
/// Properties:
/// * [variant] - Variant: \"original\", \"thumb\", or \"medium\". Defaults to \"original\".
@BuiltValue()
abstract class PhotoBytesQuery
    implements Built<PhotoBytesQuery, PhotoBytesQueryBuilder> {
  /// Variant: \"original\", \"thumb\", or \"medium\". Defaults to \"original\".
  @BuiltValueField(wireName: r'variant')
  String? get variant;

  PhotoBytesQuery._();

  factory PhotoBytesQuery([void updates(PhotoBytesQueryBuilder b)]) =
      _$PhotoBytesQuery;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhotoBytesQueryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhotoBytesQuery> get serializer =>
      _$PhotoBytesQuerySerializer();
}

class _$PhotoBytesQuerySerializer
    implements PrimitiveSerializer<PhotoBytesQuery> {
  @override
  final Iterable<Type> types = const [PhotoBytesQuery, _$PhotoBytesQuery];

  @override
  final String wireName = r'PhotoBytesQuery';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhotoBytesQuery object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.variant != null) {
      yield r'variant';
      yield serializers.serialize(
        object.variant,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PhotoBytesQuery object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object,
            specifiedType: specifiedType)
        .toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PhotoBytesQueryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'variant':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.variant = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PhotoBytesQuery deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhotoBytesQueryBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}
