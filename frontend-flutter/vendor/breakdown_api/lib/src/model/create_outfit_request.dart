// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_outfit_request.g.dart';

/// Create an outfit for a character. `piece_ids` may be empty (an empty shell establishes a named look before the garments are catalogued); layering is permitted, and piece existence is pre-checked at this edge.
///
/// Properties:
/// * [characterId]
/// * [name]
/// * [pieceIds]
@BuiltValue()
abstract class CreateOutfitRequest
    implements Built<CreateOutfitRequest, CreateOutfitRequestBuilder> {
  @BuiltValueField(wireName: r'character_id')
  String get characterId;

  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'piece_ids')
  BuiltList<String>? get pieceIds;

  CreateOutfitRequest._();

  factory CreateOutfitRequest([void updates(CreateOutfitRequestBuilder b)]) =
      _$CreateOutfitRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateOutfitRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateOutfitRequest> get serializer =>
      _$CreateOutfitRequestSerializer();
}

class _$CreateOutfitRequestSerializer
    implements PrimitiveSerializer<CreateOutfitRequest> {
  @override
  final Iterable<Type> types = const [
    CreateOutfitRequest,
    _$CreateOutfitRequest
  ];

  @override
  final String wireName = r'CreateOutfitRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateOutfitRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'character_id';
    yield serializers.serialize(
      object.characterId,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.pieceIds != null) {
      yield r'piece_ids';
      yield serializers.serialize(
        object.pieceIds,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateOutfitRequest object, {
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
    required CreateOutfitRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'character_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.characterId = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'piece_ids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.pieceIds.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateOutfitRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateOutfitRequestBuilder();
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
