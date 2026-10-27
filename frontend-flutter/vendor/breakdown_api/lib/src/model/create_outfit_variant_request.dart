// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_outfit_variant_request.g.dart';

/// Fork an existing outfit into an independent copy. Omitted fields inherit from the source outfit, which the handler reads at the API edge (the only legitimate read-model consumer per the CQRS boundary).
///
/// Properties:
/// * [name]
/// * [notes]
/// * [pieceIds]
@BuiltValue()
abstract class CreateOutfitVariantRequest
    implements
        Built<CreateOutfitVariantRequest, CreateOutfitVariantRequestBuilder> {
  @BuiltValueField(wireName: r'name')
  String? get name;

  @BuiltValueField(wireName: r'notes')
  String? get notes;

  @BuiltValueField(wireName: r'piece_ids')
  BuiltList<String>? get pieceIds;

  CreateOutfitVariantRequest._();

  factory CreateOutfitVariantRequest(
          [void updates(CreateOutfitVariantRequestBuilder b)]) =
      _$CreateOutfitVariantRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateOutfitVariantRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateOutfitVariantRequest> get serializer =>
      _$CreateOutfitVariantRequestSerializer();
}

class _$CreateOutfitVariantRequestSerializer
    implements PrimitiveSerializer<CreateOutfitVariantRequest> {
  @override
  final Iterable<Type> types = const [
    CreateOutfitVariantRequest,
    _$CreateOutfitVariantRequest
  ];

  @override
  final String wireName = r'CreateOutfitVariantRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateOutfitVariantRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.notes != null) {
      yield r'notes';
      yield serializers.serialize(
        object.notes,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.pieceIds != null) {
      yield r'piece_ids';
      yield serializers.serialize(
        object.pieceIds,
        specifiedType: const FullType.nullable(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateOutfitVariantRequest object, {
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
    required CreateOutfitVariantRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.name = valueDes;
          break;
        case r'notes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.notes = valueDes;
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
  CreateOutfitVariantRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateOutfitVariantRequestBuilder();
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
