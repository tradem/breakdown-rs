// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'outfit_decision.g.dart';

/// Reviewer decision for one outfit row of a draft row. An outfit is accepted or rejected *independently of its scene* (spec `ai-import`: the preview exposes each outfit row for its own decision). Rejecting an outfit rejects its pieces with it — they belong to that look.
///
/// Properties:
/// * [accepted] - `false` rejects the outfit: no `Piece` and no `Outfit` is created and the scene row is unaffected.
/// * [ordinal] - Index into the draft row's `outfits` list.
@BuiltValue()
abstract class OutfitDecision
    implements Built<OutfitDecision, OutfitDecisionBuilder> {
  /// `false` rejects the outfit: no `Piece` and no `Outfit` is created and the scene row is unaffected.
  @BuiltValueField(wireName: r'accepted')
  bool get accepted;

  /// Index into the draft row's `outfits` list.
  @BuiltValueField(wireName: r'ordinal')
  int get ordinal;

  OutfitDecision._();

  factory OutfitDecision([void updates(OutfitDecisionBuilder b)]) =
      _$OutfitDecision;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OutfitDecisionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OutfitDecision> get serializer =>
      _$OutfitDecisionSerializer();
}

class _$OutfitDecisionSerializer
    implements PrimitiveSerializer<OutfitDecision> {
  @override
  final Iterable<Type> types = const [OutfitDecision, _$OutfitDecision];

  @override
  final String wireName = r'OutfitDecision';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OutfitDecision object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'accepted';
    yield serializers.serialize(
      object.accepted,
      specifiedType: const FullType(bool),
    );
    yield r'ordinal';
    yield serializers.serialize(
      object.ordinal,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OutfitDecision object, {
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
    required OutfitDecisionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'accepted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.accepted = valueDes;
          break;
        case r'ordinal':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.ordinal = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OutfitDecision deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OutfitDecisionBuilder();
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
