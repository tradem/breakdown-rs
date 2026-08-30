// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/character_category.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_character_request.g.dart';

/// CreateCharacterRequest
///
/// Properties:
/// * [category]
/// * [name]
/// * [seasonId] - Opaque identifier for a `Season` aggregate.
@BuiltValue()
abstract class CreateCharacterRequest
    implements Built<CreateCharacterRequest, CreateCharacterRequestBuilder> {
  @BuiltValueField(wireName: r'category')
  CharacterCategory get category;
  // enum categoryEnum {  main_cast,  guest,  extra,  };

  @BuiltValueField(wireName: r'name')
  String get name;

  /// Opaque identifier for a `Season` aggregate.
  @BuiltValueField(wireName: r'season_id')
  String get seasonId;

  CreateCharacterRequest._();

  factory CreateCharacterRequest(
          [void updates(CreateCharacterRequestBuilder b)]) =
      _$CreateCharacterRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateCharacterRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateCharacterRequest> get serializer =>
      _$CreateCharacterRequestSerializer();
}

class _$CreateCharacterRequestSerializer
    implements PrimitiveSerializer<CreateCharacterRequest> {
  @override
  final Iterable<Type> types = const [
    CreateCharacterRequest,
    _$CreateCharacterRequest
  ];

  @override
  final String wireName = r'CreateCharacterRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateCharacterRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'category';
    yield serializers.serialize(
      object.category,
      specifiedType: const FullType(CharacterCategory),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'season_id';
    yield serializers.serialize(
      object.seasonId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateCharacterRequest object, {
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
    required CreateCharacterRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'category':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CharacterCategory),
          ) as CharacterCategory;
          result.category = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'season_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.seasonId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateCharacterRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateCharacterRequestBuilder();
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
