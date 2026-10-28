// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_outfit_origin_one_of1_inferred_from_context.g.dart';

/// Pass 2 Option B: the scene's own context (location, day, mood) implies a different look. The name is derived deterministically from that context — the script states no garment, so the look carries no pieces.
///
/// Properties:
/// * [confidence] - The Decision Model's calibrated probability of the inference.
@BuiltValue()
abstract class DraftOutfitOriginOneOf1InferredFromContext
    implements
        Built<DraftOutfitOriginOneOf1InferredFromContext,
            DraftOutfitOriginOneOf1InferredFromContextBuilder> {
  /// The Decision Model's calibrated probability of the inference.
  @BuiltValueField(wireName: r'confidence')
  double get confidence;

  DraftOutfitOriginOneOf1InferredFromContext._();

  factory DraftOutfitOriginOneOf1InferredFromContext(
          [void updates(DraftOutfitOriginOneOf1InferredFromContextBuilder b)]) =
      _$DraftOutfitOriginOneOf1InferredFromContext;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftOutfitOriginOneOf1InferredFromContextBuilder b) =>
      b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftOutfitOriginOneOf1InferredFromContext>
      get serializer =>
          _$DraftOutfitOriginOneOf1InferredFromContextSerializer();
}

class _$DraftOutfitOriginOneOf1InferredFromContextSerializer
    implements PrimitiveSerializer<DraftOutfitOriginOneOf1InferredFromContext> {
  @override
  final Iterable<Type> types = const [
    DraftOutfitOriginOneOf1InferredFromContext,
    _$DraftOutfitOriginOneOf1InferredFromContext
  ];

  @override
  final String wireName = r'DraftOutfitOriginOneOf1InferredFromContext';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftOutfitOriginOneOf1InferredFromContext object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'confidence';
    yield serializers.serialize(
      object.confidence,
      specifiedType: const FullType(double),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DraftOutfitOriginOneOf1InferredFromContext object, {
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
    required DraftOutfitOriginOneOf1InferredFromContextBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'confidence':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.confidence = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DraftOutfitOriginOneOf1InferredFromContext deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftOutfitOriginOneOf1InferredFromContextBuilder();
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
