// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/draft_outfit_origin_one_of1_inferred_from_context.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_outfit_origin_one_of1.g.dart';

/// Pass 2 Option B: the scene's own context (location, day, mood) implies a different look. The name is derived deterministically from that context — the script states no garment, so the look carries no pieces.
///
/// Properties:
/// * [inferredFromContext]
@BuiltValue()
abstract class DraftOutfitOriginOneOf1
    implements Built<DraftOutfitOriginOneOf1, DraftOutfitOriginOneOf1Builder> {
  @BuiltValueField(wireName: r'inferred_from_context')
  DraftOutfitOriginOneOf1InferredFromContext get inferredFromContext;

  DraftOutfitOriginOneOf1._();

  factory DraftOutfitOriginOneOf1(
          [void updates(DraftOutfitOriginOneOf1Builder b)]) =
      _$DraftOutfitOriginOneOf1;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftOutfitOriginOneOf1Builder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftOutfitOriginOneOf1> get serializer =>
      _$DraftOutfitOriginOneOf1Serializer();
}

class _$DraftOutfitOriginOneOf1Serializer
    implements PrimitiveSerializer<DraftOutfitOriginOneOf1> {
  @override
  final Iterable<Type> types = const [
    DraftOutfitOriginOneOf1,
    _$DraftOutfitOriginOneOf1
  ];

  @override
  final String wireName = r'DraftOutfitOriginOneOf1';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftOutfitOriginOneOf1 object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'inferred_from_context';
    yield serializers.serialize(
      object.inferredFromContext,
      specifiedType: const FullType(DraftOutfitOriginOneOf1InferredFromContext),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DraftOutfitOriginOneOf1 object, {
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
    required DraftOutfitOriginOneOf1Builder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'inferred_from_context':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(DraftOutfitOriginOneOf1InferredFromContext),
          ) as DraftOutfitOriginOneOf1InferredFromContext;
          result.inferredFromContext.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DraftOutfitOriginOneOf1 deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftOutfitOriginOneOf1Builder();
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
